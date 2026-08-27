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

      # Projects with an unresolved (pending) fraud report. They're held back
      # from the review queue and the "next" hand-out so a flagged build isn't
      # served to a reviewer until the fraud team clears it — the project stays
      # reachable directly, it's just not auto-offered.
      def fraud_flagged_project_ids
        ::Project::Report.pending.where(reason: "fraud").select(:project_id)
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

      # Drops the submissions this reviewer skipped within the cooldown window.
      # Per-reviewer: another reviewer's queue is unaffected, so a skip hides a
      # submission from the skipper without taking it out of circulation.
      def not_skipped_by(user)
        return all if user.blank?

        skipped = Certification::ReviewSkip.active
          .where(user_id: user.id, reviewable_type: polymorphic_name)
          .select(:reviewable_id)
        where.not(id: skipped)
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
      locals[:feedback_image_urls] = feedback_image_slack_urls
      SendSlackDmJob.perform_later(
        HARDWARE_REVIEW_CHANNEL,
        nil,
        blocks_path: "notifications/hardware/review_decided_channel",
        locals: locals
      )
    rescue StandardError => e
      Rails.logger.error("#{self.class.name} ##{id} post_verdict_to_hardware_review_channel! failed: #{e.message}")
    end

    # Public, Slack-renderable URLs for the reviewer's attached feedback photos so
    # the verdict channel post can show them inline. Only funding requests carry
    # feedback images; Slack won't render our webp variants, so this serves a PNG
    # one. A bad image never takes down the verdict post - it just drops out.
    def feedback_image_slack_urls
      return [] unless respond_to?(:feedback_images) && feedback_images.attached?

      routes = Rails.application.routes.url_helpers
      url_opts = (Rails.application.config.action_controller.default_url_options || {})
                   .reverse_merge(host: "stardance.hackclub.com", protocol: "https")

      feedback_images.filter_map do |image|
        next unless image.persisted?

        routes.rails_representation_url(
          image.variant(resize_to_limit: [ 1600, 1600 ], format: :png), **url_opts
        )
      rescue StandardError => e
        Rails.logger.error("feedback_image_slack_urls (##{id}) failed: #{e.message}")
        nil
      end
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

    # The feedback split into ordered blocks for display: a run of prose lines
    # becomes a :prose segment and a run of "- " lines an :items segment, in the
    # order the reviewer wrote them. feedback_prose and action_items flatten the
    # whole thing (for the digest and the resubmission gate); this keeps the
    # bullets in place, so a closing line written after the list still renders
    # after the list rather than being hoisted above it.
    def feedback_segments
      segments = []
      prose = []

      flush_prose = lambda do
        text = prose.join.strip
        segments << { type: :prose, text: text } unless text.empty?
        prose.clear
      end

      feedback.to_s.each_line do |line|
        if (item = line.chomp[ACTION_ITEM_LINE, 1])
          flush_prose.call
          if segments.last && segments.last[:type] == :items
            segments.last[:items] << item
          else
            segments << { type: :items, items: [ item ] }
          end
        else
          prose << line
        end
      end
      flush_prose.call

      segments
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
    # has since been rewound to pending by the builder disputing it, or decided
    # by a later reviewer. Read from PaperTrail because disputing restores the
    # status in place and a later verdict overwrites the reviewer, so the record
    # itself keeps no trace - and whoever picks it up next needs to know it has
    # already been round this loop once. `internal_reason` holds why;
    # `misfiling_flag` holds who raised it and when.
    def previously_misfiled?
      misfiling_version.present?
    end

    # Who flagged this review as belonging in the other hardware queue, and when,
    # reconstructed from PaperTrail. `nil` unless previously_misfiled?. The flag
    # is raised behind the reviewer's claim, so the flagger is the record's
    # reviewer at the moment of the flag - which the live record no longer holds
    # once the flag is disputed away or a later verdict reassigns it.
    def misfiling_flag
      version = misfiling_version
      return nil unless version

      { reviewer: misfiling_reviewer(version), at: version.created_at }
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

    # The most recent PaperTrail version that flipped this record into `misfiled`.
    # Memoized: previously_misfiled? and misfiling_flag both read it on the same
    # instance, and each read otherwise scans the whole version list.
    def misfiling_version
      return @misfiling_version if defined?(@misfiling_version)

      # PaperTrail records enum changes by name ("pending" -> "misfiled"), except
      # the create version, which carries the raw integer. Accept either.
      misfiled_value = self.class.statuses["misfiled"]
      @misfiling_version = versions.reverse_each.find do |version|
        change = version.changeset["status"]
        change.is_a?(Array) && (change.last.to_s == "misfiled" || change.last == misfiled_value)
      end
    rescue StandardError
      @misfiling_version = nil
    end

    # The reviewer on the record at the moment it was flagged. Prefer the change
    # itself (set when a reviewer flags without holding the claim); otherwise the
    # reviewer was already claimed and unchanged by the flag, so reify the
    # pre-flag snapshot to recover it.
    def misfiling_reviewer(version)
      reviewer_id = version.changeset.dig("reviewer_id", 1) || version.reify&.reviewer_id
      reviewer_id && User.find_by(id: reviewer_id)
    rescue StandardError
      nil
    end

    # action_items and feedback_prose each scan the feedback with the regex, and
    # both are read several times per timeline render. Parse once and memoize,
    # keyed on the feedback so an edit on the same record re-parses.
    def parsed_feedback
      return @parsed_feedback if @parsed_feedback && @parsed_feedback[:source] == feedback

      @parsed_feedback = {
        source: feedback,
        # Frozen: the memo is shared across reads, so an in-place mutation by a
        # caller would corrupt every later action_items/digest read on this record.
        items: feedback.to_s.each_line.filter_map { |line| line.chomp[ACTION_ITEM_LINE, 1] }.freeze,
        prose: feedback.to_s.each_line.reject { |line| ACTION_ITEM_LINE.match?(line.chomp) }.join.strip.freeze
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
