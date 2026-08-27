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

      # An undo can land between #complete enqueuing this job and it running.
      # Never write a submission row for a review that's back in the queue.
      if review.pending?
        Rails.logger.info "[YswsAirtableSyncJob] Skipping review ##{review.id}: back to pending"
        return
      end

      Rails.logger.info "[YswsAirtableSyncJob] Starting sync for review ##{review.id}"

      # Check if this review has already been submitted to unified DB
      check_stardance_review_submitted_unified(review)

      # Check if user is banned
      rejection_info = check_user_status(review)

      # Build Airtable fields
      fields = build_airtable_fields(review, rejection_info)

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

    # Both certification_ysws_reviews and certification_integrities key
    # uniquely on the ship event, so a review maps 1-1 to an integrity check.
    # Every synced review must have one — a missing record is a data error.
    # Raises StandardError (not RecordNotFound, which this job discards) so
    # the rescue_from handler reports it to Sentry.
    def integrity_check_for(review)
      Certification::Integrity.find_by(ship_event_id: review.post_ship_event_id) ||
        raise(StandardError, "No certification integrity for ship event ##{review.post_ship_event_id} (ysws_review ##{review.id})")
    end

    def check_stardance_review_submitted_unified(review)
      # Fetch existing Airtable record by review_id
      existing_record = ::Certification::YswsAirtable.record_for(review.id)

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
      elsif !review.project.hardware? && integrity_check_for(review).banned?
        {
          rejected: true,
          rejection_reason: "Manual fraud check rejected"
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

    def build_airtable_fields(review, rejection_info)
      user = review.user
      project = review.project
      devlog_reviews = review.devlog_reviews.to_a

      # User PII and address
      user_data = extract_user_data(user)
      primary_address = user_data[:addresses]&.first || {}

      integrity_check = project.hardware? ? nil : integrity_check_for(review)

      # Calculate minutes. When the fraud department deducted hours during
      # integrity review, those come off the reviewer-approved total before we
      # report the override hours to Airtable. Hardware projects skip integrity
      # checks entirely so there is never a deduction.
      total_original_minutes = devlog_reviews.sum { |dr| dr.original_minutes.to_i }
      total_approved_minutes = review.approved_minutes_total
      deducted_minutes = integrity_check&.deducted? ? integrity_check.deduction_minutes.to_i : 0
      net_approved_minutes = [ total_approved_minutes - deducted_minutes, 0 ].max
      hours_spent = (net_approved_minutes / 60.0).round(2)

      # Check if all devlogs rejected OR under threshold
      all_rejected = devlog_reviews.all? { |dr| dr.rejected? }
      under_min_threshold = total_approved_minutes < ::Certification::Ysws::MIN_APPROVED_MINUTES

      # Determine final rejection status
      final_rejected = review.review_rejected? || rejection_info[:rejected]
      final_rejection_reason = if rejection_info[:rejected]
        rejection_info[:rejection_reason]
      elsif all_rejected
        summary = generate_ai_summary(review).presence || review.summary_justification.presence || ""
        "Rejected by YSWS reviewer because: #{summary}".strip
      elsif under_min_threshold
        "Rejected because under #{::Certification::Ysws::MIN_APPROVED_MINUTES} approved minutes."
      else
        nil
      end

      # Get ship cert info. ship_cert_id_value is the Airtable upsert key, so it
      # keeps falling back to the ship event id to stay unique per review; the
      # cert itself resolves through the project for reships (see
      # Certification::Ysws#effective_ship_cert).
      ship_cert_id_value = review.ship_cert_id&.to_s || review.post_ship_event_id&.to_s
      ship_cert = review.effective_ship_cert

      # Get shop orders
      approved_orders = user.shop_orders
        .where(aasm_state: "fulfilled")
        .where("fulfilled_by IS NULL OR fulfilled_by NOT LIKE ?", "System%")
        .includes(:shop_item)

      # Build justification using the ideal format
      justification = build_justification(
        review: review,
        integrity_check: integrity_check,
        devlog_reviews: devlog_reviews,
        total_original_minutes: total_original_minutes,
        total_approved_minutes: total_approved_minutes,
        deducted_minutes: deducted_minutes,
        ship_cert: ship_cert,
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
        "ship_certifier" => ship_certifier_name(ship_cert), # tik
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

        # Certification integrity (hardware projects skip integrity checks)
        "integrity_id" => integrity_check&.id&.to_s,
        "integrity_status" => integrity_check&.status || "not_applicable",
        "integrity_flags" => integrity_check&.flags || 0,
        "fraud_data" => integrity_check&.fraud_detection_data&.to_json,

        # Double-dip flag
        "flagged_double_dipped" => ::Certification::UnifiedYswsService.double_dipped?(project.repo_url)
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

    # One line per Certification::Integrity status, embedded in the
    # justification. Uses fetch so an unmapped new status fails loudly.
    INTEGRITY_JUSTIFICATION_NOTES = {
      "auto_passed" => "Passed automatic heartbeat checks.",
      "pending" => "Waiting for manual heartbeat review.",
      "manually_passed" => "Passed manual heartbeat review.",
      "deducted" => "Hours deducted during manual review.",
      "banned" => "Project rejected due to manual review of heartbeats."
    }.freeze

    def ship_certifier_name(ship_cert)
      ship_cert&.reviewer&.display_name || ship_cert&.reviewer&.email || "Unknown"
    end

    def build_justification(review:, integrity_check:, devlog_reviews:, total_original_minutes:, total_approved_minutes:, deducted_minutes:, ship_cert:, approved_orders:)
      project_id = review.project_id
      ysws_review_id = review.id
      reviewer_name = review.reviewer&.display_name || review.reviewer&.email || "Unknown"

      # Format minutes
      original_formatted = format_minutes(total_original_minutes)
      approved_formatted = format_minutes(total_approved_minutes)
      adjusted_note = total_original_minutes == total_approved_minutes ? "" : " (This was adjusted to #{approved_formatted} after review.)"

      # Devlog tallies for the summary line
      approved_count = devlog_reviews.count(&:approved?)
      rejected_count = devlog_reviews.count(&:rejected?)
      approval_summary = "Of which #{approved_count} #{approved_count == 1 ? "was" : "were"} approved"
      approval_summary += " and #{rejected_count} rejected" if rejected_count.positive?

      # Per-devlog breakdown: minutes, status, and the reviewer's justification
      devlog_list = devlog_reviews.map do |dr|
        minutes = dr.approved_minutes || 0
        devlog_note = dr.justification.presence
        line = "devlog #{dr.post_devlog_id}: #{minutes} min #{dr.status}"
        line += ": \"#{devlog_note}\"" if devlog_note
        line
      end.join("\n")

      # A review counts as a project update when it carries an update description
      # or an earlier review of the same project exists (a reship).
      project_updated = review.project&.update_description.present? || prior_review?(review)

      intro = "The user logged #{original_formatted} on hackatime.#{adjusted_note}"
      intro += "\n#{commit_activity_sentence(review, total_original_minutes)}"
      intro += "\nThis is a project update." if project_updated
      if deducted_minutes.positive?
        deducted_hours = (deducted_minutes / 60.0).round(2)
        deduction_explanation = "Further deducted by #{deducted_hours} hours by the fraud department for hour fraud."
        deduction_explanation += " Reason: #{integrity_check.decision_justification}" if integrity_check&.decision_justification.present?
        intro += "\n#{deduction_explanation}"
      end

      integrity_note = integrity_check ? INTEGRITY_JUSTIFICATION_NOTES.fetch(integrity_check.status) : "Hardware project — integrity check not applicable."

      # A project with no ship cert at all can't be linked — say so rather than
      # emitting a URL with an empty id, which reads as a broken review link.
      ship_cert_line = if ship_cert
        "The Ship Cert is at https://stardance.hackclub.com/admin/certification/ship/#{ship_cert.id}"
      else
        "No ship certification was issued for this project."
      end

      justification = <<~JUSTIFICATION
        #{intro}

        In this time they wrote #{devlog_reviews.count} devlogs. #{approval_summary}.

        This project was initially ship certified by #{ship_certifier_name(ship_cert)}.

        Following this it was YSWS reviewed by #{reviewer_name}

        #{devlog_list}
        ====================================================

        #{integrity_note}

        The Stardance project can be found at https://stardance.hackclub.com/projects/#{project_id}

        The Full YSWS Review + devlogs are at https://stardance.hackclub.com/admin/certification/review/#{ysws_review_id}

        #{ship_cert_line}
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

      # Identify the Hackatime account behind the hours so reviewers can look it
      # up directly, then list the project names linked to this project.
      hackatime_uid = review.user&.hackatime_identity&.uid
      justification += "\n\nUser's Hackatime ID: #{hackatime_uid.presence || "none linked"}"

      hackatime_project_names = review.project&.hackatime_projects&.distinct&.pluck(:name) || []
      justification += if hackatime_project_names.any?
        "\n\nUser's Hackatime Project Names: #{hackatime_project_names.join(", ")}"
      else
        "\n\nNo hackatime projects linked :cry:"
      end

      justification.strip
    end

    # Rates whole-project commit activity against total logged hours: all repo
    # commits between project creation and this ship event, over the hours
    # derived from the summed devlog-review original minutes (the same raw
    # baseline shown at the front of the justification). Degrades to an
    # "unavailable" line instead of raising — git-host flakiness or a missing
    # repo URL shouldn't block the sync.
    def commit_activity_sentence(review, total_original_minutes)
      project = review.project
      provider = GitHost::Base.for(project&.repo_url)
      return "Commit activity could not be checked (no supported repo URL)." unless provider

      commit_count = provider.fetch_commits(
        since: project.created_at,
        before: review.post_ship_event&.created_at || Time.current
      ).size
      hours = total_original_minutes / 60.0
      return "They had #{commit_count} commits, but no logged hours to compare against." unless hours.positive?

      per_hour = commit_count / hours
      rating = per_hour > 1 ? "good" : per_hour > 0.8 ? "okay" : "BAD"

      "They had #{commit_count} commits, which compared to the original #{hours.round(1)} logged hours is \"#{rating}\" (#{per_hour.round(2)} commits/hour)."
    rescue StandardError => e
      Rails.logger.warn "[YswsAirtableSyncJob] commit activity check failed: #{e.class}: #{e.message}"
      "Commit activity could not be checked (fetch failed)."
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

    # True when an earlier review exists for the same project (i.e. this is a
    # reship). Mirrors the prior-review lookup on the YSWS review page.
    def prior_review?(review)
      Certification::Ysws
        .where(project_id: review.project_id)
        .where("id < ?", review.id)
        .exists?
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
      @table ||= ::Certification::YswsAirtable.table
    end
  end
end
