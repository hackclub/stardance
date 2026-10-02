# Syncs an approved funding request to Airtable.
# Uses the same field schema as YswsAirtableSyncJob so downstream
# automations work identically for both record types.
module Certification
  class FundingRequestAirtableSyncJob < ApplicationJob
    include Rails.application.routes.url_helpers

    queue_as :literally_whenever

    rescue_from(StandardError) do |error|
      Sentry.capture_exception(error, level: :fatal,
        message: "FundingRequestAirtableSyncJob failed for funding_request ##{arguments.first}: #{error.message}",
        extra: { funding_request_id: arguments.first })
      raise error
    end

    retry_on Faraday::Error, wait: :exponentially_longer, attempts: 3 do |job, error|
      Sentry.capture_exception(error, level: :fatal,
        message: "FundingRequestAirtableSyncJob failed for funding_request ##{job.arguments.first}: #{error.message}",
        extra: { funding_request_id: job.arguments.first })
    end
    retry_on Faraday::TimeoutError, wait: 30.seconds, attempts: 2 do |job, error|
      Sentry.capture_exception(error, level: :fatal,
        message: "FundingRequestAirtableSyncJob failed for funding_request ##{job.arguments.first}: #{error.message}",
        extra: { funding_request_id: job.arguments.first })
    end
    discard_on ActiveRecord::RecordNotFound

    def perform(funding_request_id)
      @funding_request = Certification::FundingRequest
        .includes(:reviewer, :user, project: { banner_attachment: :blob })
        .find(funding_request_id)

      return unless @funding_request.approved?

      Rails.logger.info "[FundingRequestAirtableSyncJob] Starting sync for funding_request ##{@funding_request.id}"

      fields = build_airtable_fields
      table.upsert(fields, "ship_cert_id")

      @funding_request.update_column(:airtable_synced_at, Time.current)

      Rails.logger.info "[FundingRequestAirtableSyncJob] Successfully synced funding_request ##{@funding_request.id}"
    end

    private

    def build_airtable_fields
      user = @funding_request.user
      project = @funding_request.project
      user_data = extract_user_data(user)
      primary_address = user_data[:addresses]&.first || {}

      banner_url = banner_url_for_project(project)
      screenshot_attachments = banner_url.present? ? [ { "url" => banner_url } ] : []

      {
        # Identity — prefixed to avoid collisions with YSWS ship_cert_id values
        "ship_cert_id" => "funding_request_#{@funding_request.id}",
        "review_id" => "funding_request_#{@funding_request.id}",

        # User PII
        "user_slack_id" => user_data[:slack_id],
        "Email" => user_data[:email],
        "First Name" => user_data[:first_name],
        "Last Name" => user_data[:last_name],
        "user_display_name" => user_data[:display_name],
        "Birthday" => user_data[:birthday],
        "How did you hear about this?" => user.ref,

        # Address
        "Address (Line 1)" => primary_address["line_1"],
        "Address (Line 2)" => primary_address["line_2"],
        "City" => primary_address["city"],
        "State / Province" => primary_address["state"],
        "ZIP / Postal Code" => primary_address["postal_code"],
        "Country" => primary_address["country"],

        # Project
        "project_name" => project.title,
        "ai_declaration" => project.ai_declaration,
        "project_update_description" => project.update_description,
        "Code URL" => project.repo_url,
        "Playable URL" => project.demo_url,
        "readme_url" => project.readme_url,
        "Description" => project.description,
        "Screenshot" => screenshot_attachments,

        # Review Data
        "reviewer" => @funding_request.reviewer&.display_name || @funding_request.reviewer&.email || "Unknown",
        "ship_certifier" => nil,
        "reviewed_at" => @funding_request.decided_at&.iso8601,
        "ship_certed_at" => nil,
        "airtable_synced_at" => Time.current.iso8601,

        # Hours
        "Optional - Override Hours Spent" => hackpad_project? ? 10 : hours_at_submission,
        "Optional - Override Hours Spent Justification" => build_justification,
        "hours_pre_deflation" => hours_at_submission,
        "is_hardware" => true,

        # Rejection — these are approved, so no rejection
        "rejection_reason" => nil,
        "rejected_at" => nil,

        # Ship event timestamps — not applicable
        "ship_end" => nil,
        "ship_start" => nil,

        # Report status
        "report_status" => report_status,

        # Integrity — not applicable for funding requests
        "integrity_id" => nil,
        "integrity_status" => "not_applicable",
        "integrity_flags" => 0,
        "fraud_data" => nil,

        # Double-dip flag
        "flagged_double_dipped" => ::Certification::UnifiedYswsService.double_dipped?(project.repo_url),

        # Hackatime
        "hackatime_uid" => user.hackatime_identity&.uid,
        "hackatime_keys" => project.hackatime_keys.join(",").presence,

        # Devlogs snapshot
        "devlogs_json" => build_devlogs_json
      }
    end

    def build_justification
      mission_slug = @funding_request.project.current_mission&.slug

      case mission_slug
      when "blare"
        "BLARE_MISSION"
      when "hackpad"
        build_hackpad_justification
      else
        build_custom_justification
      end
    end

    def build_custom_justification
      project = @funding_request.project
      submitted_at = @funding_request.created_at&.strftime("%Y-%m-%d %H:%M UTC")
      total_hours = hours_at_submission || 0
      requested = @funding_request.requested_amount_cents ? "$#{"%.2f" % (@funding_request.requested_amount_cents / 100.0)}" : "N/A"
      approved = @funding_request.approved_amount_cents ? "$#{"%.2f" % (@funding_request.approved_amount_cents / 100.0)}" : "N/A"

      <<~TEXT.strip
        This is a hardware design submitted to Stardance on #{submitted_at}

        Authors had to log their hours either through lapse or hackatime, and concurrently post devlogs of their progress. Through this, they logged #{total_hours} hours at the time of submission.

        note that some projects had JOURNAL.md files which were converted into devlogs instead.

        It was then reviewed by the following reviewers:

        #{verdict_history}

        Other data:

        Tier: #{@funding_request.tier_code || "N/A"}
        Requested amount: #{requested}
        Approved amount: #{approved}

        The Stardance project can be found at https://stardance.hackclub.com/projects/#{project.id}
      TEXT
    end

    def build_hackpad_justification
      project = @funding_request.project
      total_hours = hours_at_submission || 0

      <<~TEXT.strip
        This is a hackpad that was submitted to stardance

        Authors were pointed to log their hours either through lapse or hackatime, and concurrently post devlogs of their progress. Through this, they logged #{total_hours} hours at the time of submission.

        note that some projects had JOURNAL.md files which were converted into devlogs instead.

        It was then reviewed by the following reviewers:

        #{verdict_history}

        Because consistent timetracking was not strictly enforced, many hackpads are missing time. This, in addition to the 600+ hackpads that have manually had their time checked in the ~2 years the program has been running, means that we are setting all hackpad designs to 10 hours (despite the median being 15) unless it is of note, in which case there will be a justification below indicating otherwise.

        The Stardance project can be found at https://stardance.hackclub.com/projects/#{project.id}
      TEXT
    end

    def extract_user_data(user)
      latest_order = user.shop_orders
        .where.not(frozen_address_ciphertext: nil)
        .where(aasm_state: "fulfilled")
        .order(fulfilled_at: :desc)
        .first

      addresses = latest_order&.frozen_address ? [ latest_order.frozen_address ] : []

      {
        slack_id: user.slack_id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        display_name: user.display_name,
        birthday: user.birthday,
        addresses: addresses
      }
    end

    def public_url_options
      return @public_url_options if defined?(@public_url_options)

      raw = Rails.application.config.asset_host.presence || ENV["APP_HOST"].presence
      @public_url_options =
        if raw.blank?
          {}
        else
          raw = "https://#{raw}" unless raw.match?(%r{\Ahttps?://})
          uri = URI.parse(raw)
          options = { host: uri.host, protocol: uri.scheme }
          options[:port] = uri.port if uri.port && ![ 80, 443 ].include?(uri.port)
          options
        end
    rescue URI::InvalidURIError => e
      Rails.logger.error("[FundingRequestAirtableSyncJob] invalid asset_host/APP_HOST (#{raw.inspect}): #{e.message}")
      @public_url_options = {}
    end

    def blob_url(attachment)
      return nil if attachment.nil?

      options = public_url_options
      if options[:host].blank?
        Rails.logger.error("[FundingRequestAirtableSyncJob] no public host configured (asset_host / APP_HOST) — attachment URL skipped")
        return nil
      end

      rails_storage_proxy_url(attachment, **options)
    rescue StandardError => e
      Rails.logger.error("[FundingRequestAirtableSyncJob] blob_url error: #{e.class}: #{e.message}")
      nil
    end

    def banner_url_for_project(project)
      banner = project.display_banner
      return nil unless banner&.attached?

      blob_url(banner)
    end

    def build_devlogs_json
      devlogs = @funding_request.project
        .devlogs
        .includes(:post, attachments_attachments: :blob)
        .joins(:post)
        .where(posts: { created_at: ...@funding_request.created_at })
        .order(created_at: :asc)

      devlogs.map do |devlog|
        image_urls = devlog.attachments.select(&:image?).filter_map { |a| blob_url(a) }

        {
          id: devlog.id,
          body: devlog.body,
          duration_seconds: devlog.duration_seconds,
          hours: devlog.duration_seconds ? (devlog.duration_seconds / 3600.0).round(2) : 0,
          phase: devlog.phase,
          created_at: devlog.created_at.iso8601,
          images: image_urls
        }
      end.to_json
    end

    def hours_at_submission
      return @hours_at_submission if defined?(@hours_at_submission)

      total_seconds = @funding_request.project
        .devlogs
        .joins(:post)
        .where(posts: { created_at: ...@funding_request.created_at })
        .sum(:duration_seconds)

      @hours_at_submission = (total_seconds / 3600.0).round(2)
    end

    def hackpad_project?
      @funding_request.project.current_mission&.slug == "hackpad"
    end

    def verdict_history
      requests = @funding_request.project
        .certification_funding_requests
        .where.not(decided_at: nil)
        .includes(:reviewer)
        .order(decided_at: :asc)

      requests.map do |fr|
        name = fr.reviewer&.display_name || fr.reviewer&.email || "Unknown"
        at = fr.decided_at.strftime("%Y-%m-%d %H:%M UTC")
        "#{fr.status.capitalize} by #{name} at #{at}"
      end.join("\n")
    end

    def report_status
      user = @funding_request.user
      project = @funding_request.project

      if user.banned?
        "banned"
      elsif Project::Report.where(project_id: project.id, status: :pending).exists?
        "pending_reports"
      else
        ""
      end
    end

    def table
      @table ||= ::Certification::YswsAirtable.table
    end
  end
end
