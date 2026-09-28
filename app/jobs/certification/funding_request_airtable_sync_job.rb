# Syncs an approved funding request to Airtable.
# Triggered when a reviewer approves a hardware design funding request.
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

      return unless @funding_request.decided?

      Rails.logger.info "[FundingRequestAirtableSyncJob] Starting sync for funding_request ##{@funding_request.id}"

      fields = build_airtable_fields
      table.upsert(fields, "funding_request_id")

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

      {
        "funding_request_id" => @funding_request.id.to_s,

        # User PII
        "user_slack_id" => user_data[:slack_id],
        "Email" => user_data[:email],
        "First Name" => user_data[:first_name],
        "Last Name" => user_data[:last_name],
        "user_display_name" => user_data[:display_name],
        "Birthday" => user_data[:birthday],

        # Address
        "Address (Line 1)" => primary_address["line_1"],
        "Address (Line 2)" => primary_address["line_2"],
        "City" => primary_address["city"],
        "State / Province" => primary_address["state"],
        "ZIP / Postal Code" => primary_address["postal_code"],
        "Country" => primary_address["country"],

        # Project
        "project_name" => project.title,
        "project_id" => project.id.to_s,
        "Code URL" => project.repo_url,
        "Playable URL" => project.demo_url,
        "Description" => project.description,
        "Screenshot" => banner_url.present? ? [ { "url" => banner_url } ] : [],

        # Funding details
        "complexity_tier" => @funding_request.tier_code,
        "requested_amount_cents" => @funding_request.requested_amount_cents,
        "approved_amount_cents" => @funding_request.approved_amount_cents,
        "status" => @funding_request.status,
        "feedback" => @funding_request.feedback,
        "submitter_note" => @funding_request.submitter_note,
        "issues_grant" => @funding_request.issues_grant?,
        "awards_design_kit" => @funding_request.awards_design_kit?,
        "hcb_grant_hashid" => @funding_request.hcb_grant_hashid,

        # Review data
        "reviewer" => @funding_request.reviewer&.display_name || @funding_request.reviewer&.email || "Unknown",
        "decided_at" => @funding_request.decided_at&.iso8601,
        "airtable_synced_at" => Time.current.iso8601
      }
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

    def table
      @table ||= ::Certification::YswsAirtable.table
    end
  end
end
