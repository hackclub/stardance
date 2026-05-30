# Syncs a completed YSWS review to Airtable
# Triggered when a reviewer clicks "Complete Review" in the YSWS admin interface
module Certification
  module Ysws
    class AirtableSyncJob < ApplicationJob
      include Rails.application.routes.url_helpers

      queue_as :default

      # Retry configuration for network errors
      retry_on Faraday::Error, wait: :exponentially_longer, attempts: 5
      retry_on Faraday::TimeoutError, wait: 30.seconds, attempts: 3
      discard_on ActiveRecord::RecordNotFound

      def perform(ysws_review_id)
        review = find_review(ysws_review_id)
        return unless review

        Rails.logger.info "[Certification::Ysws::AirtableSyncJob] Starting sync for review ##{review.id}"

        # Check if user is banned
        rejection_info = check_user_status(review)

        # Generate AI summary of devlog justifications (optional)
        ai_summary = generate_ai_summary(review)

        # Build Airtable fields
        fields = build_airtable_fields(review, ai_summary, rejection_info)

        # Upsert to Airtable
        table.upsert(fields, "ship_cert_id")

        # Update sync timestamp
        review.update_column(:airtable_synced_at, Time.current)

        Rails.logger.info "[Certification::Ysws::AirtableSyncJob] Successfully synced review ##{review.id}"
      rescue StandardError => e
        Rails.logger.error "[Certification::Ysws::AirtableSyncJob] Failed to sync review ##{ysws_review_id}: #{e.message}"
        Sentry.capture_exception(e, extra: {
          ysws_review_id: ysws_review_id,
          user_id: review&.user_id,
          project_id: review&.project_id
        })
        raise
      end

      private

      def find_review(ysws_review_id)
        Certification::Ysws
          .includes(
            :reviewer,
            :ship_cert,
            :post_ship_event,
            user: { shop_orders: :shop_item },
            project: { banner_attachment: :blob },
            devlog_reviews: { post_devlog: { attachments_attachments: :blob } }
          )
          .find_by(id: ysws_review_id)
      end

      def check_user_status(review)
        user = review.user

        if user.banned?
          {
            rejected: true,
            rejection_reason: "User banned: #{user.banned_reason || 'No reason provided'}"
          }
        else
          { rejected: false, rejection_reason: nil }
        end
      end

      def generate_ai_summary(review)
        devlog_reviews = review.devlog_reviews.to_a
        return nil if devlog_reviews.empty?

        # Collect all devlog justifications
        justifications = devlog_reviews
          .map { |dr| dr.justification.presence }
          .compact

        return nil if justifications.empty?

        # Use OpenRouter API to summarize (similar to SupportVibecheckJob)
        prompt = <<~PROMPT
          Summarize the following YSWS review justifications into one concise justification (2-3 sentences maximum).
          Focus on the key points and reasoning for approving or rejecting devlogs.

          JUSTIFICATIONS:
          #{justifications.map.with_index(1) { |j, i| "#{i}. #{j}" }.join("\n")}

          OUTPUT:
          Return only the summary text, no formatting or explanations.
        PROMPT

        response = Faraday.post("https://openrouter.ai/api/v1/chat/completions") do |req|
          req.headers["Authorization"] = "Bearer #{ENV['OPENROUTER_API_KEY']}"
          req.headers["Content-Type"] = "application/json"
          req.options.timeout = 10
          req.body = {
            model: "x-ai/grok-4.1-fast",
            messages: [
              { role: "user", content: prompt }
            ]
          }.to_json
        end

        if response.success?
          body = JSON.parse(response.body)
          content = body.dig("choices", 0, "message", "content")
          content&.strip
        else
          Rails.logger.warn "[Certification::Ysws::AirtableSyncJob] AI summarization failed: #{response.status}"
          nil
        end
      rescue StandardError => e
        Rails.logger.warn "[Certification::Ysws::AirtableSyncJob] AI summarization error: #{e.message}"
        nil # Gracefully fall back to nil if AI fails
      end

      def build_airtable_fields(review, ai_summary, rejection_info)
        user = review.user
        project = review.project
        devlog_reviews = review.devlog_reviews.to_a

        # User PII and address
        user_data = extract_user_data(user)
        primary_address = user_data[:addresses]&.first || {}

        # Calculate minutes
        total_original_minutes = devlog_reviews.sum { |dr| dr.original_minutes.to_i }
        total_approved_minutes = devlog_reviews.sum { |dr| dr.approved_minutes.to_i }
        hours_spent = (total_approved_minutes / 60.0).round(2)

        # Check if all devlogs rejected OR under 6 minutes
        all_rejected = devlog_reviews.all? { |dr| dr.rejected? }
        under_min_threshold = total_approved_minutes < 6

        # Determine final rejection status
        final_rejected = rejection_info[:rejected] || all_rejected || under_min_threshold
        final_rejection_reason = if rejection_info[:rejected]
          rejection_info[:rejection_reason]
        elsif all_rejected
          summary = ai_summary.presence || review.summary_justification.presence || ""
          "Rejected by YSWS reviewer because: #{summary}".strip
        elsif under_min_threshold
          "Rejected because under 6 approved minutes."
        else
          nil
        end

        # Get ship cert info
        ship_cert_id_value = review.ship_cert_id&.to_s || review.post_ship_event_id&.to_s
        ship_cert = review.ship_cert
        ship_certifier_name = ship_cert&.reviewer&.display_name || ship_cert&.reviewer&.email || "Unknown"

        # Get shop orders
        approved_orders = user.shop_orders
          .where(aasm_state: "fulfilled")
          .where("fulfilled_by IS NULL OR fulfilled_by NOT LIKE ?", "System%")
          .includes(:shop_item)

        # Build justification using the ideal format
        justification = build_justification(
          review: review,
          devlog_reviews: devlog_reviews,
          total_original_minutes: total_original_minutes,
          total_approved_minutes: total_approved_minutes,
          ship_certifier_name: ship_certifier_name,
          ai_summary: ai_summary,
          approved_orders: approved_orders
        )

        # Get media URLs
        banner_url = banner_url_for_project(project)
        video_thumbnail_url = video_thumbnail_url_for_ship_event(review.post_ship_event)

        {
          # Identity
          "review_id" => review.id.to_s,
          "ship_cert_id" => ship_cert_id_value,

          # User PII
          "slack_id" => user_data[:slack_id],
          "Email" => user_data[:email],
          "First Name" => user_data[:first_name],
          "Last Name" => user_data[:last_name],
          "display_name" => user_data[:display_name],
          "Birthday" => user_data[:birthday],

          # Address
          "Address (Line 1)" => primary_address["line_1"],
          "Address (Line 2)" => primary_address["line_2"],
          "City" => primary_address["city"],
          "State / Province" => primary_address["state"],
          "ZIP / Postal Code" => primary_address["postal_code"],
          "Country" => primary_address["country"],

          # Project
          "Code URL" => project.repo_url,
          "Playable URL" => project.demo_url,
          "project_readme" => project.readme_url,
          "Description" => project.description,
          "Screenshot" => [
            banner_url.present? ? { "url" => banner_url } : nil,
            video_thumbnail_url.present? ? { "url" => video_thumbnail_url } : nil
          ].compact,

          # Review Data
          "reviewer" => review.reviewer&.display_name || review.reviewer&.email || "Unknown",
          "synced_at" => Time.current.iso8601,

          # Hours and Justification
          "Optional - Override Hours Spent" => hours_spent,
          "Optional - Override Hours Spent Justification" => justification,

          # Rejection
          "rejected_project" => final_rejected,
          "rejection_reason" => final_rejection_reason,

          # Report status
          "report_status" => report_status(review)
        }
      end

      def extract_user_data(user)
        # Get address from most recent fulfilled shop order
        latest_order = user.shop_orders
          .where.not(frozen_address: nil)
          .where(aasm_state: "fulfilled")
          .order(fulfilled_at: :desc)
          .first

        addresses = latest_order&.frozen_address ? [latest_order.frozen_address] : []

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

      def build_justification(review:, devlog_reviews:, total_original_minutes:, total_approved_minutes:, ship_certifier_name:, ai_summary:, approved_orders:)
        project_id = review.project_id
        ysws_review_id = review.id
        ship_cert_id = review.ship_cert_id
        reviewer_name = review.reviewer&.display_name || review.reviewer&.email || "Unknown"

        # Format minutes
        original_formatted = format_minutes(total_original_minutes)
        approved_formatted = format_minutes(total_approved_minutes)

        # Build devlog approval list
        approved_devlogs = devlog_reviews.select { |dr| dr.approved? }
        devlog_list = approved_devlogs.map do |dr|
          "devlog #{dr.post_devlog_id}: #{dr.approved_minutes} min"
        end.join("\n")

        # YSWS justification (use AI summary if available, otherwise use summary_justification)
        ysws_justification = ai_summary.presence ||
                            review.summary_justification.presence ||
                            "No specific justification provided."

        justification = <<~JUSTIFICATION
          The user logged #{original_formatted} on hackatime. #{total_original_minutes == total_approved_minutes ? "" : "(This was adjusted to #{approved_formatted} after review.)"}

          In this time they wrote #{devlog_reviews.count} devlogs.

          This project was initially ship certified by #{ship_certifier_name}.

          Following this it was YSWS reviewed by #{reviewer_name}

          who mentioned: #{ysws_justification}

          and approved:

          #{devlog_list}
          ====================================================
          The Stardance project can be found at https://stardance.hackclub.com/projects/#{project_id}

          The Full YSWS Review + devlogs are at https://stardance.hackclub.com/admin/certification/ysws/#{ysws_review_id}

          The Ship Cert is at https://stardance.hackclub.com/admin/certification/ship_cert/#{ship_cert_id}/
        JUSTIFICATION

        # Add shop orders section if available
        if approved_orders.any?
          manual_orders = approved_orders.reject { |order| order.fulfilled_by&.start_with?("System") }
          if manual_orders.any?
            orders_list = manual_orders.last(2).map do |order|
              item_name = order.shop_item.name
              fulfilled_by = order.fulfilled_by.presence || "Unknown"
              fulfilled_at = order.fulfilled_at&.strftime("%Y-%m-%d") || "Unknown date"
              "#{item_name} (x#{order.quantity}) - approved by #{fulfilled_by} on #{fulfilled_at}"
            end.join("\n")

            justification += "\n\nThis user has the following manually approved shop orders:\n#{orders_list}"
          end
        end

        justification.strip
      end

      def format_minutes(minutes)
        hours = minutes / 60
        remaining_minutes = minutes % 60
        hours > 0 ? "#{hours}h #{remaining_minutes}min" : "#{remaining_minutes}min"
      end

      def banner_url_for_project(project)
        return nil unless project.banner.attached?

        host = ENV["APP_HOST"]
        return nil if host.blank?

        rails_blob_url(project.banner, host: host)
      rescue StandardError => e
        Rails.logger.error("[Certification::Ysws::AirtableSyncJob] banner_url error: #{e.message}")
        nil
      end

      def video_thumbnail_url_for_ship_event(ship_event)
        return nil unless ship_event

        video_attachment = ship_event.attachments.find { |a| a.video? }
        return nil unless video_attachment

        host = ENV["APP_HOST"]
        return nil if host.blank?

        rails_blob_url(video_attachment, host: host)
      rescue StandardError => e
        Rails.logger.error("[Certification::Ysws::AirtableSyncJob] video_thumbnail_url error: #{e.message}")
        nil
      end

      def report_status(review)
        user = review.user
        project = review.project

        if user.banned?
          "banned"
        elsif Project::Report.where(project_id: project.id, status: :pending).exists?
          "pending_reports"
        else
          ""
        end
      end

      def table
        @table ||= Norairrecord.table(
          airtable_api_key,
          airtable_base_id,
          table_name
        )
      end

      def table_name
        Rails.application.credentials.dig(:ysws_review, :airtable_table_name) ||
          ENV["YSWS_REVIEW_AIRTABLE_TABLE"] ||
          "YSWS Project Submission"
      end

      def airtable_api_key
        Rails.application.credentials.dig(:ysws_review, :airtable_api_key) ||
          Rails.application.credentials&.airtable&.api_key ||
          ENV["AIRTABLE_API_KEY"]
      end

      def airtable_base_id
        Rails.application.credentials.dig(:ysws_review, :airtable_base_id) ||
          ENV["YSWS_REVIEW_AIRTABLE_BASE_ID"]
      end
    end
  end
end
