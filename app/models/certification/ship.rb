# == Schema Information
#
# Table name: certification_ship_reviews
#
#  id                        :bigint           not null, primary key
#  bonus_stardust            :float
#  claim_expires_at          :datetime
#  claimed_at                :datetime
#  decided_at                :datetime
#  feedback                  :text
#  internal_reason           :text
#  lock_version              :integer          default(0), not null
#  proof_video_url           :string
#  recert_reason             :text
#  stardust_earned           :float
#  status                    :integer          default(0), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  external_certification_id :string
#  post_ship_event_id        :bigint
#  project_id                :bigint           not null
#  returned_by_id            :bigint
#  reviewer_id               :bigint
#
# Indexes
#
#  idx_on_status_claim_expires_at_c7a5e87a52                      (status,claim_expires_at)
#  index_certification_ship_reviews_on_decided_at                 (decided_at)
#  index_certification_ship_reviews_on_external_certification_id  (external_certification_id) UNIQUE
#  index_certification_ship_reviews_on_post_ship_event_id         (post_ship_event_id)
#  index_certification_ship_reviews_on_reviewer_id                (reviewer_id)
#  index_ship_reviews_unique_pending_project                      (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
#  fk_rails_...  (post_ship_event_id => post_ship_events.id) ON DELETE => nullify
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#
module Certification
  class Ship < ApplicationRecord
    self.table_name = "certification_ship_reviews"

    include Certification::Reviewable

    belongs_to :project
    # Same record as :project but visible through soft deletion, so submitter
    # history can still name projects deleted after a verdict.
    belongs_to :project_with_deleted, -> { with_deleted }, class_name: "Project",
               foreign_key: :project_id, optional: true
    belongs_to :reviewer, class_name: "User", optional: true
    belongs_to :returned_by, class_name: "User", optional: true
    belongs_to :post_ship_event, class_name: "Post::ShipEvent", optional: true

    has_paper_trail

    # The reviewer records a walkthrough and passes it along with the verdict.
    has_one_attached :verdict_video

    # Admins can force-delete shipped projects; fall through to the deleted
    # record so review pages (and submitter history cards linking to them)
    # still render instead of crashing on a nil project.
    def project
      super || project_with_deleted
    end

    def owner
      @owner ||= project.memberships.owner.order(:created_at).first&.user
    end

    def verdict_ship_event
      post_ship_event || project&.last_ship_event
    end

    # misfiled: a reviewer says this belongs in the design queue and the builder
    # hasn't answered yet. withdrawn: the builder agreed, so the ship is rolled
    # back and the project returns to the design stage. Neither is a verdict, so
    # both stay out of the approval-rate and decision tallies.
    enum :status, {
      pending: 0,
      approved: 1,
      returned: 2,
      misfiled: 3,
      withdrawn: 4
    }, default: :pending

    EXTERNAL_DECISION_MAP = { "APPROVED" => :approved, "REJECTED" => :returned }.freeze
    EXTERNAL_CERTIFICATION_ID_PATTERN = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/
    PROOF_VIDEO_URL_MAX_LENGTH = 2_048
    PROOF_VIDEO_URL_PATTERN = %r{\Ahttps?://\S+\z}

    def assign_external_certification_id!(cert_id)
      cert_id = cert_id.to_s
      return :skipped if cert_id.blank?
      return :skipped unless cert_id.match?(EXTERNAL_CERTIFICATION_ID_PATTERN)
      return :skipped if external_certification_id.present?

      update!(external_certification_id: cert_id)
      :persisted
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      restore_attributes([ :external_certification_id ])
      :skipped
    end

    def transfer_external_certification_id_to!(other)
      return false if external_certification_id.blank?
      return false if other.external_certification_id.present?

      uuid = external_certification_id
      transaction do
        update!(external_certification_id: nil)
        other.update!(external_certification_id: uuid)
      end
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      reload
      other.reload
      false
    end

    ACCEPTED_VIDEO_TYPES = %w[video/mp4 video/webm video/quicktime].freeze

    # Canned request-changes responses offered on the review form. The opener
    # is the standard wording Shipwrights use for low-quality submissions;
    # reviewers replace the bullets with the specific changes they want.
    FEEDBACK_TEMPLATES = [
      {
        label: "Doesn't meet quality standards",
        body: <<~TEXT.strip
          Hey! Thanks for shipping your project. It's not quite ready for voting yet, so here's what we'd like you to change:
          - Change 1
          - Change 2
          - Change 3
          Once you've made these, ship it again and we'll take another look!
        TEXT
      },
      {
        label: "AI-generated look & feel",
        body: <<~TEXT.strip
          Hey! Thanks for shipping your project. It's not quite ready for voting yet, so here's what we'd like you to change:
          - Rework the CSS, right now it looks like every other AI-made site. Give it your own style.
          - Add a couple of features you came up with yourself to make it more fun to use.
          Once you've made these, ship it again and we'll take another look!
        TEXT
      }
    ].freeze

    validates :feedback, length: { maximum: 10_000 }, allow_blank: true
    validates :proof_video_url, length: { maximum: PROOF_VIDEO_URL_MAX_LENGTH },
                                format: { with: PROOF_VIDEO_URL_PATTERN, message: "must be an http(s) URL" },
                                allow_blank: true
    validates :verdict_video,
              content_type: { in: ACCEPTED_VIDEO_TYPES, spoofing_protection: true }
    validates :bonus_stardust,
              numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
              allow_nil: true

    scope :for_reviewer, ->(user) {
      joins(:project)
        .where(projects: { deleted_at: nil })
        .where.not(project_id: user.memberships.select(:project_id))
    }

    scope :by_project_type, ->(type) {
      type == "unclassified" \
        ? joins(:project).where(projects: { project_type: nil })
        : joins(:project).where(projects: { project_type: type })
    }

    # A hardware ship is certified in the hardware build queue
    # (Admin::Certification::HardwareReviewsController), which selects the same
    # rows with `hardware_stage IS NOT NULL`. This is the other half of that
    # split: without it one review sits in both queues and a shipwright gets
    # handed a build cert they aren't reviewing for.
    #
    # Deliberately not folded into `for_reviewer`/`available_for` — the hardware
    # queue builds on those, so narrowing them there would empty it.
    scope :software_only, -> { joins(:project).where(projects: { hardware_stage: nil }) }

    # The other half: what the global hardware build queue can actually hand a
    # reviewer. A cert on a soft-deleted project is unreachable from every dash,
    # and a hardware mission's certs are reviewed on that mission's own dash, so
    # counting either against this queue reports a backlog nobody can work.
    scope :in_global_hardware_queue, -> { joins(:project).merge(::Project.hardware.without_hardware_mission) }
    # The other half: certifications a hardware mission reviews on its own dash.
    scope :in_hardware_mission_queue, -> { joins(:project).merge(::Project.hardware.with_hardware_mission) }

    def self.available_for(user)
      # Chained AFTER the merge on purpose: `merge` would replace this project_id
      # filter with for_reviewer's own project_id condition and drop the fraud
      # hold-back. A pending fraud report keeps the project out of the queue
      # until the fraud team clears it.
      super.merge(for_reviewer(user)).where.not(project_id: fraud_flagged_project_ids)
    end

    # Claim-next for the software queue. The hardware queue has its own
    # candidate lookup, so this narrowing stays on Ship rather than the concern.
    def self.next_eligible_scope(user)
      super.software_only
    end

    # Health target for the pending queue. Above this we read as "behind".
    QUEUE_TARGET = 25

    # Target turnaround: a ship should get a verdict within this many days.
    SLA_DAYS = 3

    # Snapshot of queue health for the reviewer dashboard. Counts are global
    # (every reviewer shares one queue), so this is intentionally not scoped
    # to the current user the way the listing is. Software only, so the header
    # numbers agree with the rows the shipwright is actually shown.
    def self.dashboard_stats(now: Time.current)
      today = now.beginning_of_day
      week = now.beginning_of_week
      base = software_only
      approved_count = base.where(status: :approved).count
      returned_count = base.where(status: :returned).count
      decided_count = approved_count + returned_count

      decided = base.decided

      pending_ages = base.where(status: :pending).pluck(:created_at)
      median_pending_wait = if pending_ages.any?
        sorted = pending_ages.map { |t| now - t }.sort
        (median_value(sorted) / 3600.0).round(1)
      end

      # Table-qualified: `base` joins projects, which has its own created_at.
      avg_decision_secs = decided.where.not(decided_at: nil)
        .average(Arel.sql("EXTRACT(EPOCH FROM (certification_ship_reviews.decided_at - certification_ship_reviews.created_at))"))
      avg_decision_hours = avg_decision_secs ? (avg_decision_secs / 3600.0).round(1) : nil

      {
        pending: pending_ages.size,
        approved: approved_count,
        returned: returned_count,
        decided: decided_count,
        approval_rate: decided_count.zero? ? nil : (approved_count * 100.0 / decided_count).round(1),
        decisions_today: decided.where(decided_at: today..).count,
        new_today: base.where(created_at: today..).count,
        decisions_this_week: decided.where(decided_at: week..).count,
        new_this_week: base.where(created_at: week..).count,
        oldest_pending: base.where(status: :pending).order(created_at: :asc).first,
        queue_target: QUEUE_TARGET,
        sla_days: SLA_DAYS,
        overdue_pending: base.where(status: :pending)
                             .where("certification_ship_reviews.created_at < ?", now - SLA_DAYS.days).count,
        median_pending_wait_hours: median_pending_wait,
        avg_decision_hours: avg_decision_hours
      }
    end

    def self.reviewer_daily_data(days: 30, now: Time.current)
      start = (now.to_date - (days - 1)).to_time.beginning_of_day
      approved_int = statuses[:approved]
      returned_int = statuses[:returned]

      rows = where("decided_at >= ?", start)
        .decided
        .joins(:reviewer)
        .group(Arel.sql("DATE(decided_at)"), "users.id", "users.display_name")
        .select(
          Arel.sql("DATE(decided_at) AS day"),
          "users.id AS reviewer_id",
          "users.display_name",
          "COUNT(*) AS total",
          Arel.sql("SUM(CASE WHEN status = #{approved_int} THEN 1 ELSE 0 END) AS approved_count"),
          Arel.sql("SUM(CASE WHEN status = #{returned_int} THEN 1 ELSE 0 END) AS returned_count")
        )
        .to_a

      return [] if rows.empty?

      dates = (0...days).map { |i| now.to_date - (days - 1 - i) }

      rows.group_by(&:reviewer_id)
        .sort_by { |_, rs| -rs.sum(&:total) }
        .map do |_, reviewer_rows|
          by_date = reviewer_rows.index_by { |r| r.day.to_date }
          {
            name: reviewer_rows.first.display_name,
            data: dates.map { |date|
              r = by_date[date]
              { total: r&.total.to_i, approved: r&.approved_count.to_i, returned: r&.returned_count.to_i }
            }
          }
        end
    end

    def self.daily_chart_data(days: 30, now: Time.current)
      start = (now.to_date - (days - 1)).to_time.beginning_of_day
      approved_int = statuses[:approved]
      returned_int = statuses[:returned]

      decisions = where("decided_at >= ?", start)
        .decided
        .group(Arel.sql("DATE(decided_at)"))
        .select(
          Arel.sql("DATE(decided_at) AS day"),
          Arel.sql("SUM(CASE WHEN status = #{approved_int} THEN 1 ELSE 0 END) AS approved_count"),
          Arel.sql("SUM(CASE WHEN status = #{returned_int} THEN 1 ELSE 0 END) AS returned_count")
        )
        .index_by { |r| r.day.to_date }

      submitted = where("created_at >= ?", start)
        .group(Arel.sql("DATE(created_at)"))
        .count
        .transform_keys { |k| k.is_a?(Date) ? k : Date.parse(k.to_s) }

      unique_reviewers = where("decided_at >= ?", start)
        .decided
        .where.not(reviewer_id: nil)
        .group(Arel.sql("DATE(decided_at)"))
        .select(
          Arel.sql("DATE(decided_at) AS day"),
          Arel.sql("COUNT(DISTINCT reviewer_id) AS cnt")
        )
        .index_by { |r| r.day.to_date }

      queue_ships = where("created_at <= ?", now.end_of_day)
        .where("decided_at IS NULL OR decided_at >= ?", start)
        .pluck(:created_at, :decided_at)

      median_wait_by_day = where("decided_at >= ?", start)
        .decided
        .where.not(decided_at: nil)
        .pluck(:created_at, :decided_at)
        .group_by { |_, da| da.to_date }
        .transform_values do |pairs|
          hours = pairs.map { |ca, da| (da - ca) / 3600.0 }.sort
          median_value(hours).round(1)
        end

      (0...days).map do |i|
        date     = now.to_date - (days - 1 - i)
        date_end = date.to_time.end_of_day
        dec      = decisions[date]
        # O(days × fetched_ships) in-memory scan; acceptable at current table size, revisit beyond ~100k rows.
        queue    = queue_ships.count { |ca, da| ca <= date_end && (da.nil? || da > date_end) }
        {
          date: date.strftime("%-m/%-d"),
          approved: dec&.approved_count.to_i,
          returned: dec&.returned_count.to_i,
          submitted: submitted[date].to_i,
          unique_reviewers: unique_reviewers[date]&.cnt.to_i,
          queue_size: queue,
          median_wait_hours: median_wait_by_day[date]
        }
      end
    end

    # Reviewers ranked by completed decisions over a window. Returns rows of
    # { name:, count: } for :daily, :weekly, or :alltime.
    def self.leaderboard(period, now: Time.current, limit: 10)
      scope = where.not(reviewer_id: nil).decided
      case period.to_sym
      when :daily  then scope = scope.where(decided_at: now.beginning_of_day..)
      when :weekly then scope = scope.where(decided_at: now.beginning_of_week..)
      end

      scope.joins(:reviewer)
           .group("users.display_name")
           .order(Arel.sql("COUNT(*) DESC"), Arel.sql("users.display_name ASC"))
           .limit(limit)
           .count
           .map { |name, count| { name: name, count: count } }
    end

    # Verdict history across every project this user owns. Shown beside the
    # review form so Shipwrights judging a gray-area project can see whether
    # the submitter keeps getting returned for low quality. Goes through
    # memberships rather than joining projects so reviews keep counting after
    # their project is soft-deleted — deleting a returned project and
    # resubmitting is exactly the pattern this panel exists to surface.
    def self.submitter_history(user)
      owned = Project::Membership.where(user_id: user.id, role: :owner).select(:project_id)
      scope = where(project_id: owned)
      counts = scope.group(:status).count
      {
        total: counts.values.sum,
        projects: scope.distinct.count(:project_id),
        approved: counts["approved"].to_i,
        returned: counts["returned"].to_i,
        recent: scope.includes(:project_with_deleted, :reviewer, :returned_by).order(created_at: :desc).limit(6)
      }
    end

    def self.decided_today_count(reviewer_id, now: Time.current)
      where(reviewer_id: reviewer_id)
        .decided
        .where(decided_at: now.beginning_of_day..)
        .count
    end

    def self.reviewed_today(user, now: Time.current)
      decided_today_count(user.id, now: now)
    end

    MILESTONE_TIERS = [
      { min: 40, multiplier: 2.0 },
      { min: 20, multiplier: 1.75 },
      { min: 10, multiplier: 1.5 },
      { min: 5,  multiplier: 1.25 },
      { min: 0,  multiplier: 1.0 }
    ].freeze

    def self.multiplier_for_milestone(total_count)
      MILESTONE_TIERS.find { |t| total_count >= t[:min] }&.dig(:multiplier) || 1.0
    end

    def self.next_milestone(total_count)
      thresholds = MILESTONE_TIERS.map { |t| t[:min] }.reject(&:zero?).sort
      next_thresh = thresholds.find { |t| t > total_count }
      return nil if next_thresh.nil?
      { threshold: next_thresh, multiplier: multiplier_for_milestone(next_thresh), reviews_needed: next_thresh - total_count }
    end

    def self.median_value(sorted)
      n = sorted.size
      n.odd? ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    end
    private_class_method :median_value

    # Stardust earned per completed review
    REVIEW_BOUNTY = 1.25 # This will be updated once we add the project types.

    before_save :stamp_claimed_at, if: -> { will_save_change_to_reviewer_id? && reviewer_id.present? && claimed_at.nil? }
    before_save :stamp_decided_at, if: -> { will_save_change_to_status? && status_change&.last.in?(DECIDED_STATUSES) && decided_at.nil? }
    before_save :assign_stardust_earned, if: -> { will_save_change_to_status? && status_change&.last.in?(DECIDED_STATUSES) && reviewer_id.present? }
    after_save :apply_verdict_to_project!, if: :saved_change_to_status?
    after_save_commit :notify_owner!, if: -> { saved_change_to_status? && decided? }
    after_save_commit :post_verdict_to_hardware_review_channel!, if: -> { saved_change_to_status? && decided? && project&.hardware? }
    after_create_commit :post_submission_to_hardware_review_channel!, if: -> { project&.hardware? }

    # Timeline cards for decided reviews sort by when the verdict landed.
    def decided_on
      decided_at || updated_at
    end

    # Read by Notifications::Hardware::BuildReviewed to render the Slack blocks,
    # so this has to stay public.
    def notification_locals
      routes = Rails.application.routes.url_helpers
      # default_url_options is only configured in production, so a bare
      # reverse_merge on it raises NoMethodError in development and test.
      url_opts = (Rails.application.config.action_controller.default_url_options || {})
                   .reverse_merge(host: "stardance.hackclub.com", protocol: "https")

      {
        project_title: project.title,
        project_url: routes.project_url(project, **url_opts),
        approved: approved?,
        reviewer_name: reviewer&.display_name,
        feedback: feedback.to_s
      }
    end


    def queue_mismatch_flagged_label = "build certification"
    def queue_mismatch_suggested_label = "design funding"

    # Action items gate only the hardware build resubmission. Software ship
    # reviewers routinely leave "- " bullets - the returned-ship FEEDBACK_TEMPLATES
    # ship with them - so keying off dashed feedback alone would drag software
    # ships into the acknowledgment flow the hardware queue owns.
    def gates_resubmission?
      super && project&.hardware?
    end

    private

    # Read straight off the association rather than through
    # Project#last_ship_event, which deliberately skips misfiled ships - the
    # restore path has to be able to find the one it just hid.
    def queue_mismatch_ship_event
      post_ship_event || project&.ship_events&.first
    end

    def hide_from_public_surfaces!
      queue_mismatch_ship_event&.update!(certification_status: "misfiled")
    end

    def restore_to_public_surfaces!
      queue_mismatch_ship_event&.update!(certification_status: "pending")
    end

    # The builder confirmed they need funding after all: the project goes back
    # to the design stage so it can ask for a grant. Build devlogs keep their
    # phase - the hours are real, and re-filing them as design would erase time
    # the builder already logged.
    def apply_queue_conversion!
      project.converting_review_queue = true
      project.update!(hardware_stage: "design")
      project.roll_back_withdrawn_ship!
    end

    def assign_stardust_earned
      total_count = Certification::Ship.decided_today_count(reviewer_id) + 1
      multiplier = Certification::Ship.multiplier_for_milestone(total_count)
      self.stardust_earned = (REVIEW_BOUNTY * multiplier) + (bonus_stardust || 0)
    end

    def stamp_claimed_at
      self.claimed_at = Time.current
    end

    def stamp_decided_at
      self.decided_at = Time.current
    end

    def apply_verdict_to_project!
      return unless decided?
      project.with_lock do
        ship_event = verdict_ship_event
        latest = ship_event.nil? || ship_event == project.last_ship_event

        case status.to_sym
        when :approved
          ship_event&.update!(certification_status: "approved")
          if latest
            project.start_review! if project.may_start_review?
            project.approve! if project.may_approve?
          end
          create_ysws_review_for_ship(ship_event) if ship_event
          collapse_mission_build_review!(ship_event)
        when :returned
          ship_event&.update!(certification_status: "returned")
          if latest
            project.start_review! if project.may_start_review?
            project.return_for_changes! if project.may_return_for_changes?
          end
        end
      end
    end

    # Hardware missions review the build as one decision: certifying the ship
    # (just above, which cascades the mission submission to `pending`) also
    # finalizes that submission, granting the after-ship prize and any
    # achievement. Software missions keep their separate mission approval.
    def collapse_mission_build_review!(ship_event)
      submission = ship_event&.mission_submission
      return unless submission&.mission&.hardware?
      return unless submission.may_approve?

      submission.update!(reviewed_by: reviewer, reviewed_at: Time.current, rejection_message: nil)
      submission.approve!
      submission.grant_rewards!(reviewer_id: reviewer&.id)
    end

    def create_ysws_review_for_ship(ship_event)
      unless owner
        Sentry.capture_message(
          "Ship certification approved but no owner found to create YSWS review",
          level: :error,
          extra: {
            ship_cert_id: id,
            project_id: project.id,
            ship_event_id: ship_event.id
          }
        )
        return
      end

      # Create YSWS review with all devlog reviews for this ship
      Certification::YswsReviewCreator.new(
        ship_event: ship_event,
        user: owner,
        project: project,
        ship_cert_id: id
      ).call
    end

    # Software keeps the direct DM: its approval copy sends the project off to
    # voting, which hardware never enters.
    def notify_owner!
      return notify_owner_of_build! if project&.hardware?

      notify_owner_by_slack!
    end

    def notify_owner_of_build!
      Notifications::Hardware::BuildReviewed.notify(
        recipient: owner,
        actor: reviewer,
        record: self
      )
    rescue StandardError => e
      Rails.logger.error("Ship ##{id} notify_owner_of_build! failed: #{e.message}")
    end

    def notify_owner_by_slack!
      return unless owner&.slack_id.present?

      routes = Rails.application.routes.url_helpers
      url_opts = (Rails.application.config.action_controller.default_url_options || {})
                      .reverse_merge(host: "stardance.hackclub.com", protocol: "https")

      locals = {
        project_title: project.title,
        project_url: routes.project_url(project, **url_opts),
        feedback: feedback.to_s,
        video_url: if verdict_video.attached?
                     routes.rails_blob_url(verdict_video, **url_opts)
                   else
                     proof_video_url.presence
                   end
      }

      case status.to_sym
      when :approved
        msg = "Your project '#{project.title}' was approved. It's out for voting now."
        msg += "\n\nFeedback: #{feedback}" if feedback.present?

        SendSlackDmJob.perform_later(
          owner.slack_id,
          msg,
          blocks_path: "notifications/projects/approved",
          locals: locals,
          sent_by_id: reviewer_id
        )
      when :returned
        msg = "Your project '#{project.title}' needs changes before it can ship."
        msg += "\n\nFeedback: #{feedback}" if feedback.present?

        SendSlackDmJob.perform_later(
          owner.slack_id,
          msg,
          blocks_path: "notifications/projects/returned",
          locals: locals,
          sent_by_id: reviewer_id
        )
      end
    end
  end
end
