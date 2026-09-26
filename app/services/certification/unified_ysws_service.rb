module Certification
  # Read-only lookups against the Unified YSWS Airtable base — the cross-program
  # record of every approved YSWS submission. Used to spot a repo that has
  # already been submitted to another YSWS ("double dipped").
  class UnifiedYswsService
    BASE_ID  = "app3A5kJwYqxMLOgh"
    TABLE_ID = "tblzWWGUYHVH7Zyqf"

    # Program name comes from a lookup field whose separator is an en dash (–),
    # not a hyphen.
    PROGRAM_NAME_FIELD = "YSWS–Name"
    CODE_URL_FIELD     = "Code URL"
    STARDANCE_PROGRAM  = "Stardance"

    REQUEST_TIMEOUT = 10

    Submission = Data.define(:program_name, :code_url)
    Totals = Data.define(:records, :hours)

    # The unified base is fed by each program's own submission table, so the
    # hours column can carry either name depending on which automation wrote
    # the row. The first present value wins.
    HOURS_FIELDS = [ "Optional - Override Hours Spent", "Override Hours Spent", "Hours Spent" ].freeze
    PAGE_SIZE = 100

    class << self
      # Submissions of the same repo to YSWS programs other than Stardance.
      # Stardance's own records are excluded so a project doesn't flag itself.
      # Fails open with [] — a missing key or an Airtable hiccup must not block
      # a review.
      def double_dip_submissions(repo_url)
        submissions_for_repo(repo_url).reject { |submission| submission.program_name == STARDANCE_PROGRAM }
      end

      def double_dipped?(repo_url)
        double_dip_submissions(repo_url).any?
      end

      # Every Stardance row in the unified base, counted and summed by hours.
      # Pages through the whole set, so it is for a cached dashboard figure,
      # not a request path. Fails open with nil: no key, or an Airtable hiccup,
      # reads as "unknown" rather than zero.
      def stardance_totals
        key = api_key
        if key.blank?
          Rails.logger.warn "[UnifiedYswsService] totals skipped: no API key configured (UNIFIED_READ_ONLY)"
          return nil
        end

        records = 0
        hours = 0.0
        offset = nil

        loop do
          response = Faraday.get("https://api.airtable.com/v0/#{BASE_ID}/#{TABLE_ID}") do |req|
            req.params["filterByFormula"] = %Q(FIND("#{STARDANCE_PROGRAM}", ARRAYJOIN({#{PROGRAM_NAME_FIELD}})))
            req.params["pageSize"] = PAGE_SIZE
            req.params["offset"] = offset if offset
            req.headers["Authorization"] = "Bearer #{key}"
            req.options.timeout = REQUEST_TIMEOUT
          end

          unless response.success?
            Rails.logger.warn "[UnifiedYswsService] totals failed: HTTP #{response.status} — #{response.body}"
            return nil
          end

          body = JSON.parse(response.body)
          body.fetch("records", []).each do |record|
            records += 1
            hours += hours_for(record.fetch("fields", {}))
          end
          offset = body["offset"]
          break if offset.blank?
        end

        Totals.new(records: records, hours: hours.round(1))
      rescue StandardError => e
        Rails.logger.error "[UnifiedYswsService] totals error: #{e.class}: #{e.message}"
        nil
      end

      # Strips scheme, a trailing ".git", trailing slash and fragment so the
      # substring match tolerates the many ways the same repo gets pasted.
      def normalize_code_url(url)
        return "" if url.blank?

        url
          .sub(/\Ahttps?:\/\//, "")
          .sub(/(?:\.git)?\/?(?:#.*)?$/, "")
      end

      private

      def submissions_for_repo(repo_url)
        normalized = normalize_code_url(repo_url)
        return [] if normalized.blank?

        key = api_key
        if key.blank?
          Rails.logger.warn "[UnifiedYswsService] lookup skipped: no API key configured (UNIFIED_READ_ONLY)"
          return []
        end

        response = Faraday.get("https://api.airtable.com/v0/#{BASE_ID}/#{TABLE_ID}") do |req|
          req.params["filterByFormula"] = %Q(FIND("#{normalized}", {#{CODE_URL_FIELD}}))
          req.params["fields"] = [ CODE_URL_FIELD, PROGRAM_NAME_FIELD ]
          req.headers["Authorization"] = "Bearer #{key}"
          req.options.timeout = REQUEST_TIMEOUT
        end

        unless response.success?
          Rails.logger.warn "[UnifiedYswsService] lookup failed: HTTP #{response.status} — #{response.body}"
          return []
        end

        records = JSON.parse(response.body).fetch("records", [])
        Rails.logger.info "[UnifiedYswsService] lookup: #{records.size} match(es) for '#{normalized}'"

        records.map { |record| build_submission(record.fetch("fields", {})) }
      rescue StandardError => e
        Rails.logger.error "[UnifiedYswsService] lookup error: #{e.class}: #{e.message}"
        []
      end

      def hours_for(fields)
        HOURS_FIELDS.lazy.map { |field| fields[field] }.find(&:present?).to_f
      end

      def build_submission(fields)
        Submission.new(
          program_name: Array(fields[PROGRAM_NAME_FIELD]).first.presence,
          code_url: fields[CODE_URL_FIELD]
        )
      end

      def api_key
        Rails.application.credentials.dig(:unified_ysws, :airtable_api_key) ||
          ENV["UNIFIED_READ_ONLY"]
      end
    end
  end
end
