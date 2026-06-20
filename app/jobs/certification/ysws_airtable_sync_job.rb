# Syncs a completed YSWS review to Airtable
# Triggered when a reviewer clicks "Complete Review" in the YSWS admin interface
module Certification
  class YswsAirtableSyncJob < ApplicationJob
    include Rails.application.routes.url_helpers

    queue_as :default

    # rescue_from(StandardError) must be declared FIRST — ActiveJob checks handlers in reverse registration order (last = highest priority), so retry_on declarations below will take precedence over this catch-all for Faraday errors.
    rescue_from(StandardError) do |error|
      Sentry.capture_exception(error, level: :fatal, message: "YswsAirtableSyncJob failed for ysws_review ##{arguments.first}: #{error.message}", extra: { ysws_review_id: arguments.first })
      raise error
    end

    retry_on Faraday::Error, wait: :exponentially_longer, attempts: 3 do |job, error|
      Sentry.capture_exception(error, level: :fatal, message: "YswsAirtableSyncJob failed for ysws_review ##{job.arguments.first}: #{error.message}", extra: { ysws_review_id: job.arguments.first })
    end
    retry_on Faraday::TimeoutError, wait: 30.seconds, attempts: 2 do |job, error|
      Sentry.capture_exception(error, level: :fatal, message: "YswsAirtableSyncJob failed for ysws_review ##{job.arguments.first}: #{error.message}", extra: { ysws_review_id: job.arguments.first })
    end
    discard_on ActiveRecord::RecordNotFound

    def perform(ysws_review_id)
      review = find_review(ysws_review_id)
      return unless review

      Rails.logger.info "[YswsAirtableSyncJob] Starting sync for review ##{review.id}"

      # Check if this review has already been submitted to unified DB
      check_stardance_review_submitted_unified(review)

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

      Rails.logger.info "[YswsAirtableSyncJob] Successfully synced review ##{review.id}"
    end

    private

    def find_review(ysws_review_id)
      Certification::Ysws
        .includes(
          :reviewer,
          ship_cert: :reviewer,
          post_ship_event: :attachments_attachments,
          user: { shop_orders: :shop_item },
          project: { banner_attachment: :blob },
          devlog_reviews: { post_devlog: { attachments_attachments: :blob } }
        )
        .find_by(id: ysws_review_id)
    end

    def check_stardance_review_submitted_unified(review)
      # Fetch existing Airtable record by review_id
      existing_record = table.all(filter: "{review_id} = '#{review.id}'").first

      # If record exists and has "Automation - YSWS Record ID" populated, it's already in unified DB
      if existing_record && existing_record["Automation - YSWS Record ID"].present?
        raise StandardError, "This review is already in the unified db"
      end
    rescue Faraday::Error, Norairrecord::RecordNotFoundError => e
      # If Airtable fetch fails, log and allow sync to continue
      Rails.logger.warn "[YswsAirtableSyncJob] Could not check unified DB status: #{e.message}"
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

      return nil if devlog_reviews.none? { |dr| dr.justification.present? }

      # Build structured devlog entries with status, description, and justification
      devlog_entries = devlog_reviews.map.with_index(1) do |dr, i|
        devlog_body = dr.post_devlog&.body.presence || "(no description)"
        justification = dr.justification.presence || "(no justification)"
        minutes_info = "#{dr.original_minutes} min claimed"
        minutes_info += " → #{dr.approved_minutes} min approved" if dr.approved? && dr.approved_minutes != dr.original_minutes
        minutes_info = "#{dr.original_minutes} min claimed → REJECTED" if dr.rejected?

        <<~ENTRY.strip
          Devlog #{i} [#{dr.status.upcase}] (#{minutes_info}):
            Description: #{devlog_body.truncate(500)}
            Reviewer justification: #{justification}
        ENTRY
      end.join("\n\n")

      # Use OpenRouter API to summarize
      prompt = <<~PROMPT
        You are a reviewer, reviewing the reviews recieved through a program. For each devlog a user submits in a project, a review justification is paired with it.

        Your job is to summarize the following devlog reviews into a short summary 2-3 sentences long.
        Assume the summary is following the text "who mentioned:" and that the user reading the summary knows how the review process works. Assume that the overall review is a passing one (unless all devlogs have rejected status). But do note if there are any devlog reviews that mention malpractice. If there are, highlight that x devlog reviews mentioned deductions / inflation / high AI usage. Also note if any devlogs were rejected.

        DEVLOG REVIEWS:
        #{devlog_entries}

        OUTPUT:
        Return only the summary text, no formatting or explanations and keep it in first person.
      PROMPT

      response = Faraday.post("https://openrouter.ai/api/v1/chat/completions") do |req|
        req.headers["Authorization"] = "Bearer #{ENV['OPENROUTER_API_KEY']}"
        req.headers["Content-Type"] = "application/json"
        req.options.timeout = 10
        req.body = {
          model: "google/gemini-2.5-flash-lite",
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
        Rails.logger.warn "[YswsAirtableSyncJob] AI summarization failed: #{response.status}"
        nil
      end
    rescue StandardError => e
      Rails.logger.warn "[YswsAirtableSyncJob] AI summarization error: #{e.message}"
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
      total_approved_minutes = review.approved_minutes_total
      hours_spent = (total_approved_minutes / 60.0).round(2)

      # Check if all devlogs rejected OR under threshold
      all_rejected = devlog_reviews.all? { |dr| dr.rejected? }
      under_min_threshold = total_approved_minutes < ::Certification::Ysws::MIN_APPROVED_MINUTES

      # Determine final rejection status
      final_rejected = review.review_rejected?
      final_rejection_reason = if rejection_info[:rejected]
        rejection_info[:rejection_reason]
      elsif all_rejected
        summary = ai_summary.presence || review.summary_justification.presence || ""
        "Rejected by YSWS reviewer because: #{summary}".strip
      elsif under_min_threshold
        "Rejected because under #{::Certification::Ysws::MIN_APPROVED_MINUTES} approved minutes."
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
      devlog_posts = review.devlog_reviews
        .filter_map(&:post_devlog)
        .sort_by(&:created_at)
        .reverse
      posts_to_check = [ review.post_ship_event, *devlog_posts ].compact
      ship_event_screenshot_url = posts_to_check.lazy.filter_map { |p| screenshot_url_for_post(p) }.first

      # Prefer an actual ship/devlog screenshot; fall back to the project banner
      # only when there is no screenshot — never send both.
      selected_screenshot_url = ship_event_screenshot_url.presence || banner_url
      screenshot_attachments = selected_screenshot_url.present? ? [ { "url" => selected_screenshot_url } ] : []
      log_screenshot_result(review, screenshot_attachments, ship_event_screenshot_url, banner_url, posts_to_check, project)

      {
        # Identity
        "review_id" => review.id.to_s, # tik
        "ship_cert_id" => ship_cert_id_value, # tik

        # User PII
        "user_slack_id" => user_data[:slack_id], # tik
        "Email" => user_data[:email], # tik
        "First Name" => user_data[:first_name], # tik
        "Last Name" => user_data[:last_name], # tik
        "user_display_name" => user_data[:display_name], # tik
        "Birthday" => user_data[:birthday], # tik
        "How did you hear about this?" => user.ref, # tik

        # Address
        "Address (Line 1)" => primary_address["line_1"], # tik
        "Address (Line 2)" => primary_address["line_2"], # tik
        "City" => primary_address["city"], # tik
        "State / Province" => primary_address["state"], # tik
        "ZIP / Postal Code" => primary_address["postal_code"], # tik
        "Country" => primary_address["country"], # tik

        # Project
        "project_name" => project.title, # tik
        "ai_declaration" => project.ai_declaration, # tik
        "project_update_description" => project.update_description, # tik
        "Code URL" => project.repo_url, # tik
        "Playable URL" => project.demo_url, # tik
        "readme_url" => project.readme_url, # tik
        "Description" => project.description, # tik
        "Screenshot" => screenshot_attachments, # tik

        # Review Data
        "reviewer" => review.reviewer&.display_name || review.reviewer&.email || "Unknown", # tik
        "ship_certifier" => ship_certifier_name, # tik
        "reviewed_at" => review.reviewed_at&.iso8601, # tik
        "ship_certed_at" => ship_cert&.decided_at&.iso8601, # tik
        "airtable_synced_at" => Time.current.iso8601, # tik

        # Hours and Justification
        "Optional - Override Hours Spent" => hours_spent, # tik
        "Optional - Override Hours Spent Justification" => justification, # tik

        # Rejection
        "rejection_reason" => final_rejection_reason, # tik
        "rejected_at" => final_rejected ? Time.current.iso8601 : nil, # tik

        # Ship event timestamps
        "ship_end" => review.post_ship_event&.created_at&.iso8601,
        "ship_start" => (prior_ship_event(review)&.created_at || project.created_at)&.iso8601,

        # Report status
        "report_status" => report_status(review),

        # Double-dip flag
        "flagged_double_dipped" => double_dipped?(project.repo_url)
      }
    end

    def extract_user_data(user)
      # Get address from most recent fulfilled shop order
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

      ysws_justification = review.summary_justification.presence
      goi_note = ai_summary.present? ? "\n#{ai_summary}" : ""
      project_update_note = review.project.update_description.present? ? "\nProject update: #{review.project.update_description}" : ""

      justification = <<~JUSTIFICATION
        The user logged #{original_formatted} on hackatime. #{total_original_minutes == total_approved_minutes ? "" : "(This was adjusted to #{approved_formatted} after review.)"}.
        #{project_update_note}
        #{goi_note}

        In this time they wrote #{devlog_reviews.count} devlogs.

        This project was initially ship certified by #{ship_certifier_name}.

        Following this it was YSWS reviewed by #{reviewer_name}#{ysws_justification.present? ? "\n\nwho mentioned: #{ysws_justification}" : ""}

        and approved:

        #{devlog_list}
        ====================================================
        The Stardance project can be found at https://stardance.hackclub.com/projects/#{project_id}

        The Full YSWS Review + devlogs are at https://stardance.hackclub.com/admin/certification/review/#{ysws_review_id}

        The Ship Cert is at https://stardance.hackclub.com/admin/certification/ship/#{ship_cert_id}/
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

    # Active Storage URLs handed to Airtable must be ABSOLUTE and publicly
    # fetchable: Airtable downloads the file from the URL server-side, some time
    # after the upsert returns. If the URL is blank, points at a non-public host
    # (e.g. a Codespaces dev forward), or uses the wrong scheme, Airtable just
    # leaves the attachment cell empty — the upsert still returns 200 and every
    # plain-text field saves fine. So we build URLs from the app's canonical
    # public host (asset_host, set in every deployed env) and only fall back to
    # APP_HOST for local dev. Returns {} when no host is configured.
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
      Rails.logger.error("[YswsAirtableSyncJob] invalid asset_host/APP_HOST (#{raw.inspect}): #{e.message}")
      @public_url_options = {}
    end

    # Builds an absolute, single-hop proxy URL for an Active Storage attachment.
    # We use the proxy route — matching production's
    # resolve_model_to_route = :rails_storage_proxy and the url_for(attachment)
    # used throughout the views — rather than rails_blob_url. rails_blob_url
    # returns a redirect that 302s to a short-lived signed storage URL; Airtable
    # fetches some time after the upsert, so it could land on an expired target.
    # The proxy URL serves the bytes from our own host in one request and its
    # signed id does not expire.
    def blob_url(attachment)
      return nil if attachment.nil?

      options = public_url_options
      if options[:host].blank?
        Rails.logger.error("[YswsAirtableSyncJob] no public host configured (asset_host / APP_HOST) — attachment URL skipped")
        return nil
      end

      rails_storage_proxy_url(attachment, **options)
    rescue StandardError => e
      Rails.logger.error("[YswsAirtableSyncJob] blob_url error (#{attachment.class}): #{e.class}: #{e.message}")
      nil
    end

    def banner_url_for_project(project)
      banner = project.display_banner
      return nil unless banner&.attached?

      blob_url(banner)
    end

    def screenshot_url_for_post(post)
      return nil unless post

      blob_url(post.attachments.find { |a| a.image? })
    end

    # Screams when the Screenshot field comes out empty so the cause is visible
    # in logs/Sentry instead of failing silently. An empty field with source
    # images present is a real misconfiguration (host/scheme); empty with no
    # source images is expected (some reviews genuinely have no media).
    def log_screenshot_result(review, attachments, screenshot_url, banner_url, posts_to_check, project)
      if attachments.any?
        Rails.logger.info("[YswsAirtableSyncJob] review ##{review.id} Screenshot → #{attachments.map { |a| a['url'] }}")
        return
      end

      had_source_image = posts_to_check.any? { |p| p.attachments.any?(&:image?) } || project.display_banner&.attached?
      detail = "screenshot_url=#{screenshot_url.inspect} banner_url=#{banner_url.inspect} host=#{public_url_options.inspect}"

      if had_source_image
        message = "[YswsAirtableSyncJob] review ##{review.id}: source images exist but produced NO Screenshot URLs — #{detail}"
        Rails.logger.error(message)
        Sentry.capture_message(message, level: :warning, extra: { ysws_review_id: review.id })
      else
        Rails.logger.warn("[YswsAirtableSyncJob] review ##{review.id}: no Screenshot — no source images found. #{detail}")
      end
    end

    UNIFIED_YSWS_BASE_ID  = "app3A5kJwYqxMLOgh"
    UNIFIED_YSWS_TABLE_ID = "tblzWWGUYHVH7Zyqf"

    def normalize_code_url(url)
      return "" if url.blank?

      url
        .sub(/\Ahttps?:\/\//, "")
        .sub(/(?:\.git)?\/?(?:#.*)?$/, "")
    end

    def double_dipped?(repo_url)
      normalized = normalize_code_url(repo_url)
      return false if normalized.blank?

      api_key = Rails.application.credentials.dig(:unified_ysws, :airtable_api_key) ||
                ENV["UNIFIED_READ_ONLY"]

      if api_key.blank?
        Rails.logger.warn "[YswsAirtableSyncJob] double-dip check skipped: no API key configured (UNIFIED_READ_ONLY)"
        return false
      end

      filter  = %Q(FIND("#{normalized}", {Code URL}))
      encoded = URI.encode_uri_component(filter)
      url     = "https://api.airtable.com/v0/#{UNIFIED_YSWS_BASE_ID}/#{UNIFIED_YSWS_TABLE_ID}" \
                "?filterByFormula=#{encoded}&fields[]=Code%20URL"

      response = Faraday.get(url) do |req|
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.options.timeout = 10
      end

      unless response.success?
        Rails.logger.warn "[YswsAirtableSyncJob] double-dip check failed: HTTP #{response.status} — #{response.body}"
        return false
      end

      matches = JSON.parse(response.body).fetch("records", [])
      Rails.logger.info "[YswsAirtableSyncJob] double-dip check: #{matches.size} match(es) for '#{normalized}'"
      matches.any?
    rescue StandardError => e
      Rails.logger.error "[YswsAirtableSyncJob] double-dip check error: #{e.class}: #{e.message}"
      false
    end

    def prior_ship_event(review)
      ship_event = review.post_ship_event
      return nil unless ship_event

      review.project.ship_events
        .where("post_ship_events.created_at < ?", ship_event.created_at)
        .order("post_ship_events.created_at DESC")
        .first
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
