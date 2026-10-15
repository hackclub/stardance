# frozen_string_literal: true

# Read-only diagnostic for the blank "Birthday" values in the Stardance YSWS
# Airtable table. Writes nothing, anywhere — not to our database, not to
# Airtable, not to HCA. It only counts.
#
# Certification::YswsAirtableSyncJob sources the birthday from User#birthday,
# which makes a live HCA /api/v1/me call with the member's stored OAuth access
# token. Every way that can go wrong — no linked identity, a dead token, a
# payload without the field, a member who never set one — collapses to the same
# nil, so the sync job upserts Birthday => nil while still logging
# "Successfully synced". That makes the blank rows unattributable after the
# fact.
#
# This job re-runs the fetch against every member holding a reviewed YSWS
# review and separates those cases, because they point at different fixes:
#
#   - http_error 401              → the token is dead; we need refresh tokens
#                                   (we currently drop auth.credentials.refresh_token
#                                   on the floor in Sessions::HCALoginService).
#   - birthday_key_absent         → HCA is withholding the field, i.e. our
#                                   OAuth scope doesn't cover it. Same class of
#                                   bug as the dropped `address` scope — see the
#                                   comment in config/initializers/omniauth.rb.
#   - birthday_blank              → the member genuinely has no birthday at HCA.
#                                   Nothing to fix on our side.
#
# It deliberately does NOT call User#birthday: that method is exactly the thing
# whose failure modes we're trying to tell apart. The request is issued here so
# the HTTP status is visible, reusing HCAService.connection so the host and
# transport stay in one place.
#
# No birthdays, emails, or addresses are logged — only user ids, the set of KEYS
# HCA returned, and counts.
#
# Usage:
#   OneTime::AuditYswsBirthdayFetchJob.perform_now             # every eligible member
#   OneTime::AuditYswsBirthdayFetchJob.perform_now(limit: 50)  # first 50, to smoke-test
class OneTime::AuditYswsBirthdayFetchJob < ApplicationJob
  queue_as :literally_whenever

  LOG_PREFIX = "[OneTime::AuditYswsBirthdayFetch]"

  # Be a good neighbour to HCA; there's no deadline on a diagnostic.
  THROTTLE_SECONDS = 0.1
  REQUEST_TIMEOUT = 15

  # Ordered for the summary, worst-to-best, so the log reads as a funnel.
  OUTCOMES = %i[
    no_hca_identity
    blank_access_token
    http_error
    request_error
    no_identity_object
    birthday_key_absent
    birthday_blank
    birthday_unparseable
    ok
  ].freeze

  def perform(limit: nil)
    @counts = Hash.new(0)
    @statuses = Hash.new(0)
    @identity_keys = Hash.new(0)

    user_ids = eligible_user_ids(limit)
    log "starting — READ ONLY, #{user_ids.size} member(s) with a reviewed YSWS review#{limit ? " (limited to #{limit})" : ''}"

    user_ids.each_with_index do |user_id, index|
      classify(user_id)
      log "…#{index + 1}/#{user_ids.size}" if ((index + 1) % 100).zero?
    end

    report(user_ids.size)

    { counts: counts, statuses: statuses, identity_keys: identity_keys }
  end

  private
    attr_reader :counts, :statuses, :identity_keys

    # Distinct members holding at least one reviewed YSWS review — the same
    # population whose rows reach Airtable. Ordered so a limited run is
    # reproducible rather than whatever the planner returns first.
    def eligible_user_ids(limit)
      scope = ::Certification::Ysws.where.not(reviewed_at: nil)
        .distinct
        .order(:user_id)
        .pluck(:user_id)

      limit ? scope.first(limit) : scope
    end

    def classify(user_id)
      identity = ::User::Identity.hack_club.find_by(user_id: user_id)
      return record(user_id, :no_hca_identity) if identity.nil?

      token = identity.access_token
      return record(user_id, :blank_access_token) if token.blank?

      response = fetch_me(token)
      return record(user_id, :request_error) if response.nil?

      unless response.success?
        statuses[response.status] += 1
        return record(user_id, :http_error, "HTTP #{response.status}")
      end

      body = parse(response.body)
      payload = body.is_a?(Hash) ? body["identity"] : nil
      return record(user_id, :no_identity_object) unless payload.is_a?(Hash)

      # Which keys HCA actually hands back, aggregated across the run. If
      # "birthday" never appears, the field is being withheld by scope rather
      # than missing per-member.
      payload.each_key { |key| identity_keys[key] += 1 }

      # A key that isn't there at all and a key explicitly set to null mean
      # different things here, so check for presence before blankness.
      return record(user_id, :birthday_key_absent) unless payload.key?("birthday")

      raw = payload["birthday"]
      return record(user_id, :birthday_blank) if raw.blank?

      parsed = Date.parse(raw.to_s) rescue nil
      parsed ? record(user_id, :ok) : record(user_id, :birthday_unparseable)
    rescue StandardError => e
      # One member's failure must not abandon the run — the point is the totals.
      record(user_id, :request_error, "#{e.class}: #{e.message}")
    end

    # Issued here rather than through HCAService.me so the status code survives;
    # that method logs the failure and returns nil, which is precisely the
    # collapsing this job exists to undo.
    def fetch_me(access_token)
      response = HCAService.connection.get("/api/v1/me") do |req|
        req.headers["Authorization"] = "Bearer #{access_token}"
        req.headers["Accept"] = "application/json"
        req.options.timeout = REQUEST_TIMEOUT
      end
      sleep THROTTLE_SECONDS
      response
    end

    def parse(body)
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def record(user_id, outcome, detail = nil)
      counts[outcome] += 1
      # Only the unhappy paths are worth a line each; a successful fetch is
      # noise at this volume.
      log "user #{user_id} — #{outcome}#{detail ? " (#{detail})" : ''}" unless outcome == :ok
      outcome
    end

    def report(total)
      log "—" * 40
      log "scanned: #{total}"
      OUTCOMES.each { |outcome| log format("%-22s %d", outcome, counts[outcome]) }

      log "HTTP statuses seen: #{statuses.sort.map { |status, n| "#{status}×#{n}" }.join(', ').presence || 'none'}"
      log "identity payload keys seen: #{identity_keys.keys.sort.join(', ').presence || 'none'}"
      log "birthday key present in #{identity_keys['birthday']} of the payloads HCA returned"
    end

    def log(message)
      Rails.logger.info "#{LOG_PREFIX} #{message}"
    end
end
