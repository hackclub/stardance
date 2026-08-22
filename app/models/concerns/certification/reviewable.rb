module Certification
  module Reviewable
    extend ActiveSupport::Concern

    CLAIM_TTL = 30.minutes
    HARDWARE_REVIEW_CHANNEL = "C0BPN8XPSPN"

    # A reviewer's actual verdicts. The queue-routing corrections (misfiled,
    # withdrawn) are not decisions: they earn no bounty, stamp no decided_at,
    # and stay out of every queue statistic.
    DECIDED_STATUSES = %w[approved returned].freeze
    # Everything that ever counted as work in this queue. A rerouted review is
    # excluded exactly like an unsubmitted one: it got no verdict, and the work
    # reappears as its own record in the queue it belonged in.
    QUEUED_STATUSES = (DECIDED_STATUSES + %w[pending]).freeze

    class_methods do
      def decided
        where(status: DECIDED_STATUSES)
      end

      def pending_or_decided
        where(status: QUEUED_STATUSES)
      end

      def available_for(user)
        where(status: statuses[:pending]).where(
          "(reviewer_id IS NULL OR claim_expires_at IS NULL OR claim_expires_at < ?) OR reviewer_id = ?",
          Time.current, user.id
        )
      end

      def atomic_claim!(record_id, user)
        now = Time.current
        expires = now + CLAIM_TTL
        updated = where(id: record_id, status: statuses[:pending])
          .where("reviewer_id IS NULL OR claim_expires_at IS NULL OR claim_expires_at < ? OR reviewer_id = ?", now, user.id)
          .update_all(reviewer_id: user.id, claimed_at: now, claim_expires_at: expires, updated_at: now)
        updated.zero? ? nil : find(record_id)
      end

      def release_all_for(user)
        where(reviewer_id: user.id, status: statuses[:pending])
          .update_all(reviewer_id: nil, claim_expires_at: nil, updated_at: Time.current)
      end

      # Records this queue may hand out next. Defaults to everything claimable;
      # override to narrow when one model backs more than one queue.
      def next_eligible_scope(user)
        available_for(user)
      end

      def next_eligible(user, skip_ids: [])
        scope = next_eligible_scope(user)
        scope = scope.where.not(id: skip_ids) if skip_ids.any?
        scope.order(
          Arel.sql(sanitize_sql_array([ "CASE WHEN reviewer_id = ? THEN 0 ELSE 1 END", user.id ])),
          :created_at
        ).first
      end
    end

    def release_claim!
      return unless pending? && reviewer_id.present?

      self.class
        .where(id: id, status: self.class.statuses[:pending])
        .update_all(reviewer_id: nil, claim_expires_at: nil, updated_at: Time.current)
    end

    def claim_held_by?(user)
      reviewer_id == user.id && claim_expires_at.present? && claim_expires_at > Time.current
    end

    def claim_expired?
      claim_expires_at.nil? || claim_expires_at < Time.current
    end

    def post_submission_to_hardware_review_channel!
      routes = Rails.application.routes.url_helpers
      url_opts = (Rails.application.config.action_controller.default_url_options || {})
                   .reverse_merge(host: "stardance.hackclub.com", protocol: "https")

      locals = {
        project_title: project.title,
        project_url: routes.project_url(project, **url_opts),
        repo_url: project.repo_url,
        owner_slack_id: owner&.slack_id,
        owner_name: owner&.display_name,
        submission_type: is_a?(Certification::FundingRequest) ? "design" : "build"
      }
      SendSlackDmJob.perform_later(
        HARDWARE_REVIEW_CHANNEL,
        nil,
        blocks_path: "notifications/hardware/review_submitted_channel",
        locals: locals
      )
      invite_owner_to_hardware_review_channel!
    rescue StandardError => e
      Rails.logger.error("#{self.class.name} ##{id} post_submission_to_hardware_review_channel! failed: #{e.message}")
    end

    def invite_owner_to_hardware_review_channel!
      return unless owner&.slack_id.present?
      return if owner.hardware_channel_invited_at.present?

      InviteToSlackChannelJob.perform_later(owner.id, HARDWARE_REVIEW_CHANNEL)
    end

    def post_verdict_to_hardware_review_channel!
      locals = notification_locals.slice(:project_title, :project_url, :approved, :reviewer_name, :feedback)
      locals[:review_type] = is_a?(Certification::FundingRequest) ? "design" : "build"
      locals[:owner_slack_id] = owner&.slack_id
      locals[:reviewer_slack_id] = reviewer&.slack_id
      SendSlackDmJob.perform_later(
        HARDWARE_REVIEW_CHANNEL,
        nil,
        blocks_path: "notifications/hardware/review_decided_channel",
        locals: locals
      )
    rescue StandardError => e
      Rails.logger.error("#{self.class.name} ##{id} post_verdict_to_hardware_review_channel! failed: #{e.message}")
    end

    def decided?
      status.to_s.in?(DECIDED_STATUSES)
    end

    # --- action items --------------------------------------------------------

    ACTION_ITEM_LINE = /\A[[:blank:]]*-[[:blank:]]+(\S.*?)[[:blank:]]*\z/

    def action_items
      parsed_feedback[:items]
    end

    def feedback_prose
      parsed_feedback[:prose]
    end

    def gates_resubmission?
      action_items.any?
    end

    def action_items_digest
      items = action_items
      return if items.empty?

      Digest::SHA256.hexdigest(items.join("\n"))
    end

    def action_items_blocker(acknowledged:, digest:)
      return nil unless gates_resubmission?
      return :unacknowledged if digest.blank?
      return :stale unless digest == action_items_digest

      # Integer(…, exception: false) rather than to_i: the params are whatever the
      # client posted, and a hash-shaped value has no to_i.
      ticked = Array(acknowledged).filter_map { |index| Integer(index, exception: false) }
      return :unacknowledged unless action_items.each_index.all? { |index| ticked.include?(index) }

      nil
    end

    # --- wrong-queue corrections ---------------------------------------------
    #
    # A reviewer who opens a submission that belongs in the other hardware queue
    # flags it instead of deciding it. That pulls it out of their queue and puts
    # the question to the builder, who either confirms the correction (the
    # submission is withdrawn and the project switches stage) or disputes it
    # (the submission goes straight back into the queue it came from).

    def flag_queue_mismatch!(reviewer:, reason: nil)
      return false unless pending?

      transaction do
        update!(status: :misfiled, reviewer: reviewer, internal_reason: reason.presence)
        hide_from_public_surfaces!
      end
      notify_queue_mismatch!(reviewer)
      true
    end

    # The builder disagrees: put it back exactly where it was, unclaimed so the
    # next reviewer through the queue picks it up rather than the one who
    # flagged it.
    def dispute_queue_mismatch!
      return false unless misfiled?

      transaction do
        update!(status: :pending, reviewer: nil, claim_expires_at: nil, claimed_at: nil)
        restore_to_public_surfaces!
      end
      true
    end

    # The builder agrees: this submission is rolled back and the project moves to
    # the stage it should have been in. Each model supplies the stage move (and,
    # for a design request, the devlog re-filing) via `apply_queue_conversion!`.
    def confirm_queue_conversion!
      return false unless misfiled?

      transaction do
        update!(status: :withdrawn)
        apply_queue_conversion!
      end
      true
    end

    # True while the builder still owes an answer on a wrong-queue flag.
    def awaiting_queue_answer? = misfiled?

    # True when this review was flagged as wrong-queue at some point, even if it
    # has since been rewound to pending by the builder disputing it. Read from
    # PaperTrail because disputing restores the status in place, so the record
    # itself keeps no trace - and the next reviewer to pick it up needs to know
    # it has already been round this loop once. `internal_reason` holds why.
    def previously_misfiled?
      # PaperTrail records enum changes by name ("pending" -> "misfiled"), except
      # the create version, which carries the raw integer. Accept either.
      misfiled_value = self.class.statuses["misfiled"]
      versions.any? do |version|
        change = version.changeset["status"]
        next false unless change.is_a?(Array)

        change.last.to_s == "misfiled" || change.last == misfiled_value
      end
    rescue StandardError
      false
    end

    # Read by Notifications::Hardware::ReviewQueueMismatch to render the Slack
    # blocks, so this has to stay public.
    def queue_mismatch_notification_locals
      routes = Rails.application.routes.url_helpers
      # default_url_options is only configured in production, so a bare
      # reverse_merge on it raises NoMethodError in development and test.
      url_opts = (Rails.application.config.action_controller.default_url_options || {})
                   .reverse_merge(host: "stardance.hackclub.com", protocol: "https")

      {
        project_title: project.title,
        project_url: routes.project_url(project, **url_opts),
        flagged_queue: queue_mismatch_flagged_label,
        suggested_queue: queue_mismatch_suggested_label,
        reviewer_name: reviewer&.display_name,
        reason: internal_reason.to_s
      }
    end

    private

    # action_items and feedback_prose each scan the feedback with the regex, and
    # both are read several times per timeline render. Parse once and memoize,
    # keyed on the feedback so an edit on the same record re-parses.
    def parsed_feedback
      return @parsed_feedback if @parsed_feedback && @parsed_feedback[:source] == feedback

      @parsed_feedback = {
        source: feedback,
        items: feedback.to_s.each_line.filter_map { |line| line.chomp[ACTION_ITEM_LINE, 1] },
        prose: feedback.to_s.each_line.reject { |line| ACTION_ITEM_LINE.match?(line.chomp) }.join.strip
      }
    end

    # Overridden where a submission has a public artifact to hide (a ship has a
    # Post::ShipEvent on the timeline; a funding request is members-only already).
    def hide_from_public_surfaces! = nil
    def restore_to_public_surfaces! = nil

    # Routed through the notification pipeline rather than a direct Slack DM so
    # the question also lands in the in-app inbox and by email - the builder has
    # to act on it before anything else can happen.
    def notify_queue_mismatch!(reviewer)
      Notifications::Hardware::ReviewQueueMismatch.notify(
        recipient: owner,
        actor: reviewer,
        record: self
      )
    rescue StandardError => e
      Rails.logger.error("#{self.class.name} ##{id} notify_queue_mismatch! failed: #{e.message}")
    end
  end
end
