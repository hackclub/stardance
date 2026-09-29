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
        "Optional - Override Hours Spent" => hours_at_submission,
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
        "flagged_double_dipped" => ::Certification::UnifiedYswsService.double_dipped?(project.repo_url)
      }
    end

    def build_justification
      project = @funding_request.project
      reviewer_name = @funding_request.reviewer&.display_name || @funding_request.reviewer&.email || "Unknown"

      lines = []
      lines << "This is a hardware design funding request (not a YSWS review)."
      lines << "Tier: #{@funding_request.tier_code}" if @funding_request.tier_code.present?

      if @funding_request.requested_amount_cents
        lines << "Requested amount: $#{"%.2f" % (@funding_request.requested_amount_cents / 100.0)}"
      end
      if @funding_request.approved_amount_cents
        lines << "Approved amount: $#{"%.2f" % (@funding_request.approved_amount_cents / 100.0)}"
      end

      lines << "Issues HCB grant: #{@funding_request.issues_grant? ? "Yes" : "No"}"
      lines << "Awards design kit: #{@funding_request.awards_design_kit? ? "Yes" : "No"}"
      lines << "HCB grant hashid: #{@funding_request.hcb_grant_hashid}" if @funding_request.hcb_grant_hashid.present?
      lines << ""
      lines << "Reviewer feedback: #{@funding_request.feedback}" if @funding_request.feedback.present?
      lines << "Submitter note: #{@funding_request.submitter_note}" if @funding_request.submitter_note.present?
      lines << ""
      lines << "Reviewed by #{reviewer_name} on #{@funding_request.decided_at&.strftime("%Y-%m-%d")}."
      lines << ""
      lines << "The Stardance project can be found at https://stardance.hackclub.com/projects/#{project.id}"

      lines.join("\n").strip
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

    def hours_at_submission
      return @hours_at_submission if defined?(@hours_at_submission)

      total_seconds = @funding_request.project
        .devlogs
        .joins(:post)
        .where(posts: { created_at: ...@funding_request.created_at })
        .sum(:duration_seconds)

      @hours_at_submission = (total_seconds / 3600.0).round(2)
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
