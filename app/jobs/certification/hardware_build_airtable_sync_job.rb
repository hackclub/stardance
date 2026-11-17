# Syncs an approved hardware build ship to Airtable.
#
# Hardware builds never go through the GOI/YSWS queue (see
# Certification::Ysws.software_only), so the YSWS review created on approval
# would otherwise sit pending and never reach Airtable. This writes the record
# straight from the build certification instead, in the same field schema as
# FundingRequestAirtableSyncJob, and the rest is handled from Airtable.
#
# Hours are the ship's build-only hours (Post::ShipEvent#hours_at_ship): design
# time and anything before the funding request is already on the funding
# request's record, so counting it again would double it.
module Certification
  class HardwareBuildAirtableSyncJob < ApplicationJob
    include Certification::AirtableSubmission

    queue_as :literally_whenever
    self.enqueue_after_transaction_commit = true

    retry_on Faraday::Error, wait: :exponentially_longer, attempts: 3 do |job, error|
      Rails.error.report(error, severity: :error, context: { ship_cert_id: job.arguments.first, ship_event_id: job.arguments.second })
    end
    retry_on Faraday::TimeoutError, wait: 30.seconds, attempts: 2 do |job, error|
      Rails.error.report(error, severity: :error, context: { ship_cert_id: job.arguments.first, ship_event_id: job.arguments.second })
    end
    discard_on ActiveRecord::RecordNotFound

    def perform(ship_cert_id, ship_event_id)
      @ship_cert = Certification::Ship.includes(:reviewer).find(ship_cert_id)
      @ship_event = Post::ShipEvent.includes(:post).find(ship_event_id)

      return unless syncable?

      # Airtable is the source of truth: once a record exists it's never
      # overwritten, so hand edits made there survive a resync.
      if ::Certification::YswsAirtable.record_for(airtable_review_id)
        Rails.logger.info "[HardwareBuildAirtableSyncJob] Skipping ship event ##{@ship_event.id}: already in Airtable"
        return
      end

      Rails.logger.info "[HardwareBuildAirtableSyncJob] Starting sync for ship event ##{@ship_event.id}"
      table.create(build_airtable_fields)
      Rails.logger.info "[HardwareBuildAirtableSyncJob] Successfully synced ship event ##{@ship_event.id}"
    end

    private

    # A build whose YSWS review was completed by hand already synced through
    # YswsAirtableSyncJob.
    def syncable?
      @ship_cert.approved? &&
        @ship_event.certification_status == "approved" &&
        project.hardware? &&
        @ship_event.ysws_review&.reviewed_at.nil?
    end

    def project
      @ship_cert.project
    end

    def build_airtable_fields
      user = @ship_event.post.user
      user_data = extract_user_data(user)
      primary_address = user_data[:addresses]&.first || {}

      banner_url = banner_url_for_project(project)
      screenshot_attachments = banner_url.present? ? [ { "url" => banner_url } ] : []

      {
        # Identity — prefixed to avoid collisions with YSWS review_id values
        "ship_cert_id" => @ship_cert.id.to_s,
        "review_id" => airtable_review_id,
        "ship_event_id" => @ship_event.id.to_s,

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

        # Review Data — the build certification is the only review
        "reviewer" => reviewer_name(@ship_cert),
        "ship_certifier" => reviewer_name(@ship_cert),
        "reviewed_at" => @ship_cert.decided_at&.iso8601,
        "ship_certed_at" => @ship_cert.decided_at&.iso8601,
        "airtable_synced_at" => Time.current.iso8601,

        # Hours
        "Optional - Override Hours Spent" => build_hours,
        "Optional - Override Hours Spent Justification" => build_justification,
        "hours_pre_deflation" => @ship_event.window_hours.round(2),
        "is_hardware" => true,

        # Rejection — these are approved, so no rejection
        "rejection_reason" => nil,
        "rejected_at" => nil,

        # Ship event timestamps
        "ship_end" => @ship_event.post.created_at.iso8601,
        "ship_start" => (@ship_event.previous_ship_at || project.created_at)&.iso8601,

        # Report status
        "report_status" => report_status(user, project),

        # Integrity — hardware skips integrity checks
        "integrity_id" => nil,
        "integrity_status" => "not_applicable",
        "integrity_flags" => 0,
        "fraud_data" => nil,

        # Double-dip flag
        "flagged_double_dipped" => ::Certification::UnifiedYswsService.double_dipped?(project.repo_url),

        # Hackatime
        "hackatime_uid" => user.hackatime_identity&.uid,
        "hackatime_keys" => project.hackatime_keys.join(",").presence,

        # Devlogs snapshot — the ones counted towards the build hours
        "devlogs_json" => devlogs_json(build_devlogs)
      }
    end

    def airtable_review_id
      "hardware_build_#{@ship_event.id}"
    end

    def build_hours
      @ship_event.hours_at_ship.to_f.round(2)
    end

    def build_devlogs
      Post::Devlog
        .where(id: @ship_event.devlogs_in_ship_window.select(:postable_id))
        .includes(attachments_attachments: :blob)
        .order(created_at: :asc)
    end

    def build_justification
      shipped_at = @ship_event.post.created_at.strftime("%Y-%m-%d %H:%M UTC")
      certified_at = @ship_cert.decided_at&.strftime("%Y-%m-%d %H:%M UTC") || "an unknown time"
      certified_line = "The build was certified by #{reviewer_name(@ship_cert)} at #{certified_at}"
      certified_line += "\nThe build proof video is at #{@ship_cert.proof_video_url}" if @ship_cert.proof_video_url.present?

      <<~TEXT.strip
        This is a hardware build shipped to Stardance on #{shipped_at}

        Authors had to log their hours either through lapse or hackatime, and concurrently post devlogs of their progress. Through this, they logged #{build_hours} build hours in this ship. Design time and anything logged before their funding request is excluded, as it is covered by the design record.

        note that some projects had JOURNAL.md files which were converted into devlogs instead.

        #{certified_line}

        #{funding_history}

        The Stardance project can be found at https://stardance.hackclub.com/projects/#{project.id}

        The Ship Cert is at https://stardance.hackclub.com/admin/certification/ship/#{@ship_cert.id}
      TEXT
    end

    def funding_history
      requests = project.certification_funding_requests
        .approved
        .includes(:reviewer)
        .order(decided_at: :asc)
      return "This project did not go through a design funding request." if requests.none?

      lines = requests.map do |fr|
        "Funding request ##{fr.id} approved by #{reviewer_name(fr)} at #{fr.decided_at&.strftime("%Y-%m-%d %H:%M UTC")}"
      end
      "Design funding:\n#{lines.join("\n")}"
    end
  end
end
