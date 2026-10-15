# frozen_string_literal: true

# One-time backfill for blank "Birthday" values in the Stardance YSWS Airtable
# table.
#
# Why they're blank: Certification::YswsAirtableSyncJob reads the birthday from
# User#birthday, which makes a live HCA /api/v1/me call with the member's stored
# OAuth access token. Nothing refreshes that token, so once it expires HCA
# returns 401, HCAService swallows it, and the job upserts Birthday => nil while
# still logging "Successfully synced".
#
# This repairs the historical rows by re-sourcing the birthday from the Unified
# YSWS base (the cross-program record of every approved YSWS submission),
# matching on email. Coverage is partial by nature: it can only recover members
# who also shipped to another YSWS program.
#
# The Stardance Airtable table is authoritative:
#   - the set of rows to repair comes from Airtable (Birthday blank), not from
#     certification_ysws_reviews;
#   - the email used for matching is the row's own Email field, not users.email;
#   - the Stardance database is never read or written.
#
# Only the Birthday field is ever written. Nothing else on the record is
# touched, and the sync job is deliberately not re-run: it re-upserts every
# field (re-running the OpenRouter summary call), and its
# check_stardance_review_submitted_unified guard raises outright for any review
# already migrated to the unified DB.
#
# Land the "omit Birthday when nil" guard in the sync job BEFORE running with
# apply: true, otherwise the next ordinary re-sync blanks the repaired rows
# again.
#
# Usage:
#   OneTime::BackfillYswsBirthdaysFromUnifiedJob.perform_now                    # dry run, logs the plan
#   OneTime::BackfillYswsBirthdaysFromUnifiedJob.perform_now(limit: 25)         # dry run, first 25 rows
#   OneTime::BackfillYswsBirthdaysFromUnifiedJob.perform_now(apply: true)       # writes
class OneTime::BackfillYswsBirthdaysFromUnifiedJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[OneTime::BackfillYswsBirthdays]"

  EMAIL_FIELD = "Email"
  BIRTHDAY_FIELD = "Birthday"
  REVIEW_ID_FIELD = "review_id"

  # The email is interpolated into a double-quoted Airtable formula string,
  # where only a quote or a backslash could break out of the literal. Rather
  # than escape them, refuse to look up any address containing one (or
  # whitespace/control characters) — none of those can appear in an address we'd
  # match on, so an email carrying one is malformed or hostile either way.
  #
  # "@" is excluded from both halves so exactly one split point exists: an
  # ambiguous split makes the match quadratic on adversarial input, and it would
  # also let a multi-"@" string through.
  SAFE_EMAIL = /\A[^"\\@[:space:][:cntrl:]]+@[^"\\@[:space:][:cntrl:]]+\z/

  # Airtable allows 5 requests/second per base; stay well under it.
  THROTTLE_SECONDS = 0.25
  REQUEST_TIMEOUT = 15
  MAX_RETRIES = 3

  def perform(apply: false, limit: nil)
    @apply = apply
    @limit = limit
    @unified_cache = {}
    @counts = Hash.new(0)

    assert_configured!

    log "starting — #{apply ? 'APPLY (writing to Airtable)' : 'DRY RUN (no writes)'}, limit: #{limit || 'none'}"
    log "stardance: #{stardance_base_id}/#{stardance_table}, unified: #{unified_base_id}/#{unified_table_id} (read-only)"

    rows = rows_missing_birthday
    log "found #{rows.size} row(s) with a blank #{BIRTHDAY_FIELD}"

    rows.each { |row| process(row) }

    log "done — scanned: #{rows.size}, #{apply ? 'updated' : 'would update'}: #{counts[:updated]}, " \
        "no match: #{counts[:no_match]}, conflicting: #{counts[:conflict]}, " \
        "unsafe email: #{counts[:unsafe_email]}, errors: #{counts[:error]}"

    counts
  end

  private
    attr_reader :apply, :limit, :unified_cache, :counts

    def process(row)
      fields = row.fetch("fields", {})
      email = fields[EMAIL_FIELD].to_s.strip
      label = "review ##{fields[REVIEW_ID_FIELD].presence || '?'} (#{row['id']}, #{email})"

      unless email.match?(SAFE_EMAIL)
        counts[:unsafe_email] += 1
        return log "SKIP #{label} — email is not a well-formed address, not looking it up"
      end

      birthdays = cached_unified_birthdays_for(email)

      if birthdays.empty?
        counts[:no_match] += 1
        return log "SKIP #{label} — no birthday in unified"
      end

      if birthdays.size > 1
        counts[:conflict] += 1
        return log "SKIP #{label} — unified disagrees: #{birthdays.join(', ')}"
      end

      write(row, label, birthdays.first)
    end

    def write(row, label, birthday)
      unless apply
        counts[:updated] += 1
        return log "WOULD UPDATE #{label} → #{birthday}"
      end

      airtable_patch(stardance_url, stardance_api_key, row["id"], { BIRTHDAY_FIELD => birthday })
      counts[:updated] += 1
      log "UPDATED #{label} → #{birthday}"
      sleep THROTTLE_SECONDS
    rescue StandardError => e
      # One bad record must not abandon the rest of the run; the filter means a
      # re-run picks up whatever was missed.
      counts[:error] += 1
      log "ERROR #{label} — #{e.class}: #{e.message}", level: :error
    end

    # Every Stardance row missing a birthday but carrying an email to match on.
    def rows_missing_birthday
      rows = []
      offset = nil

      loop do
        params = {
          "filterByFormula" => "AND({#{BIRTHDAY_FIELD}} = BLANK(), {#{EMAIL_FIELD}} != BLANK())",
          "pageSize" => 100
        }
        [ EMAIL_FIELD, BIRTHDAY_FIELD, REVIEW_ID_FIELD ].each_with_index do |field, index|
          params["fields[#{index}]"] = field
        end
        params["offset"] = offset if offset

        body = airtable_get(stardance_url, stardance_api_key, params)
        rows.concat(body.fetch("records", []))

        offset = body["offset"]
        break if offset.blank?
        break if limit && rows.size >= limit

        sleep THROTTLE_SECONDS
      end

      limit ? rows.first(limit) : rows
    end

    # A member with several reviews costs one unified lookup, not one per row.
    def cached_unified_birthdays_for(email)
      key = email.downcase
      return unified_cache[key] if unified_cache.key?(key)

      unified_cache[key] = unified_birthdays_for(email)
      sleep THROTTLE_SECONDS
      unified_cache[key]
    end

    # Distinct birthdays recorded against this email anywhere in the unified
    # base. More than one means the source data disagrees with itself, and the
    # caller skips rather than guessing. Callers must screen the email against
    # SAFE_EMAIL first — it is interpolated straight into the lookup formula.
    def unified_birthdays_for(email)
      body = airtable_get(
        unified_url,
        unified_api_key,
        {
          "filterByFormula" => %(LOWER({#{EMAIL_FIELD}}) = "#{email.to_s.strip.downcase}"),
          "fields[0]" => EMAIL_FIELD,
          "fields[1]" => BIRTHDAY_FIELD,
          "pageSize" => 100
        }
      )

      body.fetch("records", [])
          .filter_map { |record| normalize_birthday(record.dig("fields", BIRTHDAY_FIELD)) }
          .uniq
    end

    # Airtable date fields come back as "2008-05-01" or a full ISO timestamp
    # depending on how the field is configured; normalise both to a plain ISO
    # date.
    def normalize_birthday(raw)
      return nil if raw.blank?

      Date.parse(raw.to_s).iso8601
    rescue ArgumentError
      nil
    end

    def airtable_get(url, api_key, params)
      attempt = 0

      begin
        attempt += 1
        response = Faraday.get(url) do |req|
          params.each { |key, value| req.params[key] = value }
          req.headers["Authorization"] = "Bearer #{api_key}"
          req.options.timeout = REQUEST_TIMEOUT
        end

        # 429 is a rate limit; Airtable asks for a 30s backoff.
        if response.status == 429 && attempt <= MAX_RETRIES
          sleep 30
          raise "rate limited"
        end

        raise "HTTP #{response.status} — #{response.body}" unless response.success?

        JSON.parse(response.body)
      rescue StandardError => e
        retry if attempt <= MAX_RETRIES
        raise e
      end
    end

    def airtable_patch(url, api_key, record_id, fields)
      response = Faraday.patch("#{url}/#{record_id}") do |req|
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.headers["Content-Type"] = "application/json"
        req.options.timeout = REQUEST_TIMEOUT
        req.body = { "fields" => fields }.to_json
      end

      raise "HTTP #{response.status} — #{response.body}" unless response.success?

      JSON.parse(response.body)
    end

    def airtable_url(base_id, table)
      "https://api.airtable.com/v0/#{base_id}/#{ERB::Util.url_encode(table)}"
    end

    def stardance_url = airtable_url(stardance_base_id, stardance_table)

    def unified_url = airtable_url(unified_base_id, unified_table_id)

    def assert_configured!
      missing = {
        "Stardance base id" => stardance_base_id,
        "Stardance API key" => stardance_api_key,
        "Unified API key (credentials.unified_ysws.airtable_api_key / UNIFIED_READ_ONLY)" => unified_api_key
      }.select { |_label, value| value.blank? }.keys

      raise StandardError, "#{LOG_PREFIX} missing configuration: #{missing.join(', ')}" if missing.any?
    end

    def log(message, level: :info)
      Rails.logger.public_send(level, "#{LOG_PREFIX} #{message}")
    end

    # Stardance side — same credential lookups as Certification::YswsAirtableSyncJob.
    def stardance_base_id
      Rails.application.credentials.dig(:ysws_review, :airtable_base_id) ||
        ENV["YSWS_REVIEW_AIRTABLE_BASE_ID"]
    end

    def stardance_table
      Rails.application.credentials.dig(:ysws_review, :airtable_table_name) ||
        ENV["YSWS_REVIEW_AIRTABLE_TABLE"] ||
        "YSWS Project Submission"
    end

    def stardance_api_key
      Rails.application.credentials.dig(:ysws_review, :airtable_api_key) ||
        Rails.application.credentials&.airtable&.api_key ||
        ENV["AIRTABLE_API_KEY"]
    end

    # Unified side — read-only, same base/table/credential as UnifiedYswsService.
    def unified_base_id = Certification::UnifiedYswsService::BASE_ID

    def unified_table_id = Certification::UnifiedYswsService::TABLE_ID

    def unified_api_key
      Rails.application.credentials.dig(:unified_ysws, :airtable_api_key) ||
        ENV["UNIFIED_READ_ONLY"]
    end
end
