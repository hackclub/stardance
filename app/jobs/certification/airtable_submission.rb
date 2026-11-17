# Shared plumbing for jobs that create hardware records in the "YSWS Project
# Submission" Airtable table (funding requests and builds), so both write the
# same user, address, media and report fields the downstream automations read.
module Certification
  module AirtableSubmission
    extend ActiveSupport::Concern

    included do
      include Rails.application.routes.url_helpers
    end

    private

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

    def reviewer_name(record)
      record.reviewer&.display_name || record.reviewer&.email || "Unknown"
    end

    def report_status(user, project)
      if user.banned?
        "banned"
      elsif Project::Report.where(project_id: project.id, status: :pending).exists?
        "pending_reports"
      else
        ""
      end
    end

    def devlogs_json(devlogs)
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
      Rails.logger.error("[#{self.class.name}] invalid asset_host/APP_HOST (#{raw.inspect}): #{e.message}")
      @public_url_options = {}
    end

    def blob_url(attachment)
      return nil if attachment.nil?

      options = public_url_options
      if options[:host].blank?
        Rails.logger.error("[#{self.class.name}] no public host configured (asset_host / APP_HOST) — attachment URL skipped")
        return nil
      end

      rails_storage_proxy_url(attachment, **options)
    rescue StandardError => e
      Rails.logger.error("[#{self.class.name}] blob_url error: #{e.class}: #{e.message}")
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
