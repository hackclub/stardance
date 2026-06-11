# == Schema Information
#
# Table name: certification_ship_reviews
#
#  id               :bigint           not null, primary key
#  claim_expires_at :datetime
#  claimed_at       :datetime
#  decided_at       :datetime
#  feedback         :text
#  internal_reason  :text
#  lock_version     :integer          default(0), not null
#  recert_reason    :text
#  stardust_earned  :integer
#  status           :integer          default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  project_id       :bigint           not null
#  returned_by_id   :bigint
#  reviewer_id      :bigint
#
# Indexes
#
#  idx_on_status_claim_expires_at_c7a5e87a52        (status,claim_expires_at)
#  index_certification_ship_reviews_on_decided_at   (decided_at)
#  index_certification_ship_reviews_on_reviewer_id  (reviewer_id)
#  index_ship_reviews_unique_pending_project        (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
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
      @owner ||= project.memberships.owner.first&.user
    end

    enum :status, {
      pending: 0,
      approved: 1,
      returned: 2
    }, default: :pending

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
    validates :verdict_video,
              content_type: { in: ACCEPTED_VIDEO_TYPES, spoofing_protection: true }

    scope :for_reviewer, ->(user) {
      joins(:project)
        .where(projects: { deleted_at: nil })
        .where.not(project_id: user.memberships.select(:project_id))
    }

    def self.available_for(user)
      super.merge(for_reviewer(user))
    end

    # Health target for the pending queue. Above this we read as "behind".
    QUEUE_TARGET = 25

    # Target turnaround: a ship should get a verdict within this many days.
    SLA_DAYS = 3

    # Snapshot of queue health for the reviewer dashboard. Counts are global
    # (every reviewer shares one queue), so this is intentionally not scoped
    # to the current user the way the listing is.
    def self.dashboard_stats(now: Time.current)
      today = now.beginning_of_day
      week = now.beginning_of_week
      approved_count = where(status: :approved).count
      returned_count = where(status: :returned).count
      decided_count = approved_count + returned_count

      decided = where.not(status: :pending)

      {
        pending: where(status: :pending).count,
        approved: approved_count,
        returned: returned_count,
        decided: decided_count,
        approval_rate: decided_count.zero? ? nil : (approved_count * 100.0 / decided_count).round,
        decisions_today: decided.where(decided_at: today..).count,
        new_today: where(created_at: today..).count,
        decisions_this_week: decided.where(decided_at: week..).count,
        new_this_week: where(created_at: week..).count,
        oldest_pending: where(status: :pending).order(created_at: :asc).first,
        queue_target: QUEUE_TARGET,
        sla_days: SLA_DAYS,
        overdue_pending: where(status: :pending).where("created_at < ?", now - SLA_DAYS.days).count
      }
    end

    # Reviewers ranked by completed decisions over a window. Returns rows of
    # { name:, count: } for :daily, :weekly, or :alltime.
    def self.leaderboard(period, now: Time.current, limit: 10)
      scope = where.not(reviewer_id: nil).where.not(status: :pending)
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

    # How many reviews this reviewer has decided today. Drives the momentum
    # counter on the review page, so it's scoped to the user, not the queue.
    def self.reviewed_today(user, now: Time.current)
      where(reviewer_id: user.id)
        .where.not(status: :pending)
        .where(decided_at: now.beginning_of_day..)
        .count
    end

    # Stardust earned per completed review
    REVIEW_BOUNTY = 1 # This will be updated once we add the project types.

    before_save :stamp_claimed_at, if: -> { will_save_change_to_reviewer_id? && reviewer_id.present? && claimed_at.nil? }
    before_save :stamp_decided_at, if: -> { will_save_change_to_status? && status_change&.last != "pending" && decided_at.nil? }
    before_save :assign_stardust_earned, if: -> { will_save_change_to_status? && status_change&.last != "pending" && reviewer_id.present? }
    after_save :apply_verdict_to_project!, if: :saved_change_to_status?
    after_save_commit :post_decision_to_timeline!, if: -> { saved_change_to_status? && !pending? }
    after_save_commit :notify_owner!, if: -> { saved_change_to_status? && !pending? }

    private

    def assign_stardust_earned
      self.stardust_earned = REVIEW_BOUNTY
    end

    def stamp_claimed_at
      self.claimed_at = Time.current
    end

    def stamp_decided_at
      self.decided_at = Time.current
    end

    def apply_verdict_to_project!
      return if pending?
      project.with_lock do
        project.start_review! if project.may_start_review?
        case status.to_sym
        when :approved
          project.approve! if project.may_approve?
          ship_event = project.last_ship_event
          ship_event&.update!(certification_status: "approved")
          create_ysws_review_for_ship(ship_event) if ship_event
        when :returned
          project.return_for_changes! if project.may_return_for_changes?
          ship_event = project.last_ship_event
          ship_event&.update!(certification_status: "returned")
        end
      end
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

    def post_decision_to_timeline!
      return unless owner
      return unless Flipper.enabled?(:week_1_release, owner)

      Post.create_or_find_by!(postable_type: Post::PRIVATE_SHIP_DECISION_TYPE, postable_id: id) do |post|
        post.user = owner
        post.project = project
        # Keep the card where the first verdict landed; later flips update content,
        # not timeline order.
        post.created_at = decided_at if decided_at.present?
        post.updated_at = decided_at if decided_at.present?
      end
    end

    def notify_owner!
      return unless owner&.slack_id.present?

      case status.to_sym
      when :approved
        owner.dm_user("Your project '#{project.title}' was approved. It's out for voting now.")
      when :returned
        msg = "Your project '#{project.title}' needs changes before it can ship."
        msg += "\n\n#{feedback}" if feedback.present?
        owner.dm_user(msg)
      end
    end
  end
end
