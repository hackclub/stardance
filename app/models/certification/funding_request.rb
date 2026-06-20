# == Schema Information
#
# Table name: certification_funding_requests
#
#  id                        :bigint           not null, primary key
#  approved_amount_cents     :integer
#  claim_expires_at          :datetime
#  claimed_at                :datetime
#  complexity_tier           :integer          not null
#  decided_at                :datetime
#  discount_stardust_awarded :integer
#  feedback                  :text
#  internal_reason           :text
#  lock_version              :integer          default(0), not null
#  requested_amount_cents    :integer          not null
#  stardust_earned           :integer
#  status                    :integer          default("pending"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  project_id                :bigint           not null
#  reviewer_id               :bigint
#  user_id                   :bigint           not null
#
# Indexes
#
#  idx_funding_requests_on_status_claim_expires         (status,claim_expires_at)
#  index_certification_funding_requests_on_decided_at   (decided_at)
#  index_certification_funding_requests_on_project_id   (project_id)
#  index_certification_funding_requests_on_reviewer_id  (reviewer_id)
#  index_certification_funding_requests_on_user_id      (user_id)
#  index_funding_requests_unique_pending_project        (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
module Certification
  # A hardware project owner's request for a build grant, submitted from the
  # design ("I need Funding") stage. Routes through the same reviewer queue as
  # ship certifications (Certification::Reviewable). On approval the project
  # switches to the build stage and the owner accrues an Outpost Ticket discount
  # set by the approved tier (B 30% / A 50% / S & X 100% of the ticket price).
  class FundingRequest < ApplicationRecord
    self.table_name = "certification_funding_requests"

    include Certification::Reviewable

    belongs_to :project
    belongs_to :user
    belongs_to :reviewer, class_name: "User", optional: true

    has_paper_trail

    enum :status, {
      pending: 0,
      approved: 1,
      returned: 2
    }, default: :pending

    # Complexity tiers, mirroring outpost.hackclub.com (B/A/S/X). Keyed by the
    # integer stored in complexity_tier; each carries a max grant + examples.
    TIERS = {
      1 => { code: "B", name: "B Tier", max_cents: 2_500,  discount_percent: 30,  examples: "Macropads and very basic PCBs" },
      2 => { code: "A", name: "A Tier", max_cents: 12_000, discount_percent: 50,  examples: "Keyboards and devboards" },
      3 => { code: "S", name: "S Tier", max_cents: 18_000, discount_percent: 100, examples: "Ambitious, polished builds" },
      4 => { code: "X", name: "X Tier", max_cents: 40_000, discount_percent: 100, examples: "Out of this world builds (may include a travel stipend)" }
    }.freeze

    # tier => maximum grant, in cents / dollars.
    TIER_MAX_CENTS = TIERS.transform_values { |t| t[:max_cents] }.freeze
    TIER_MAX_DOLLARS = TIER_MAX_CENTS.transform_values { |cents| cents / 100 }.freeze

    # tier => percent of the Outpost Ticket price knocked off when a design is
    # approved at that tier. Flat per tier — no longer tied to unrequested dollars.
    TIER_DISCOUNT_PERCENT = TIERS.transform_values { |t| t[:discount_percent] }.freeze

    # Stardust a reviewer earns per completed funding review.
    REVIEW_BOUNTY = 1

    # tier id => { code:, pct:, sd: } for client-side previews (funding modal).
    def self.tier_discount_summary
      TIERS.each_with_object({}) do |(id, t), summary|
        summary[id] = {
          code: t[:code],
          pct: t[:discount_percent],
          sd: (t[:discount_percent] * User::OUTPOST_TICKET_BASE / 100.0).round
        }
      end
    end

    validates :complexity_tier, inclusion: { in: TIER_MAX_CENTS.keys }
    validates :requested_amount_cents, numericality: { only_integer: true, greater_than: 0 }
    validates :approved_amount_cents,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :feedback, length: { maximum: 10_000 }, allow_blank: true
    validate :requested_within_tier_max
    validate :approved_within_tier_max
    validate :project_in_design_stage, on: :create
    validate :project_has_devlogs, on: :create
    validate :no_pending_request_exists, on: :create

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

    # Target turnaround: a request should get a verdict within this many days.
    SLA_DAYS = 3

    # Snapshot of queue health for the reviewer dashboard. Counts are global
    # (every reviewer shares one queue).
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

    # Reviewers ranked by completed decisions over a window.
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

    # How many requests this reviewer has decided today.
    def self.reviewed_today(user, now: Time.current)
      where(reviewer_id: user.id)
        .where.not(status: :pending)
        .where(decided_at: now.beginning_of_day..)
        .count
    end

    def tier = TIERS.fetch(complexity_tier, {})
    def tier_code = tier[:code]
    def tier_name = tier[:name]
    def tier_examples = tier[:examples]
    def tier_label = tier_name || "Tier #{complexity_tier}"
    def tier_max_cents = tier[:max_cents]
    def tier_max_dollars = tier_max_cents ? tier_max_cents / 100 : nil
    def tier_discount_percent = tier[:discount_percent].to_i
    # Flat Stardust knocked off the Outpost Ticket for this tier.
    def tier_discount_stardust = (tier_discount_percent * User::OUTPOST_TICKET_BASE / 100.0).round
    def requested_amount_dollars = (requested_amount_cents || 0) / 100
    def final_amount_cents = approved_amount_cents || requested_amount_cents
    def final_amount_dollars = (final_amount_cents || 0) / 100

    # Reviewers enter whole-dollar amounts; we persist cents.
    def approved_amount_dollars
      approved_amount_cents ? approved_amount_cents / 100 : nil
    end

    def approved_amount_dollars=(value)
      self.approved_amount_cents = value.present? ? value.to_i * 100 : nil
    end

    before_save :default_approved_amount,
      if: -> { will_save_change_to_status? && status_change&.last == "approved" }
    before_save :stamp_claimed_at,
      if: -> { will_save_change_to_reviewer_id? && reviewer_id.present? && claimed_at.nil? }
    before_save :stamp_decided_at,
      if: -> { will_save_change_to_status? && status_change&.last != "pending" && decided_at.nil? }
    before_save :assign_stardust_earned,
      if: -> { will_save_change_to_status? && status_change&.last != "pending" && reviewer_id.present? }
    after_save :apply_verdict_to_project!, if: :saved_change_to_status?
    after_save_commit :notify_owner!, if: -> { saved_change_to_status? && !pending? }

    private

    def project_in_design_stage
      errors.add(:base, "Only projects in the funding stage can request funding.") unless project&.design_stage?
    end

    def project_has_devlogs
      errors.add(:base, "You need to post at least one devlog before requesting funding.") unless project&.devlog_posts&.exists?
    end

    def no_pending_request_exists
      errors.add(:base, "You already have a funding request under review.") if project&.has_pending_funding_request?
    end

    def requested_within_tier_max
      return if complexity_tier.blank? || requested_amount_cents.blank?
      return unless TIER_MAX_CENTS.key?(complexity_tier)

      if requested_amount_cents > tier_max_cents
        errors.add(:requested_amount_cents, "exceeds the #{tier_label} maximum of $#{tier_max_dollars}")
      end
    end

    # Reviewers can approve for less than requested, but never above the tier max.
    def approved_within_tier_max
      return if approved_amount_cents.blank? || complexity_tier.blank?
      return unless TIER_MAX_CENTS.key?(complexity_tier)

      if approved_amount_cents > tier_max_cents
        errors.add(:approved_amount_cents, "exceeds the #{tier_label} maximum of $#{tier_max_dollars}")
      end
    end

    def default_approved_amount
      self.approved_amount_cents ||= requested_amount_cents
    end

    def assign_stardust_earned
      self.stardust_earned = REVIEW_BOUNTY
    end

    def stamp_claimed_at
      self.claimed_at = Time.current
    end

    def stamp_decided_at
      self.decided_at = Time.current
    end

    # On a decision, advance the project and (on approval) accrue the owner's
    # Outpost Ticket discount. approved_amount_cents is defaulted in a before_save
    # so it's set by the time this runs.
    def apply_verdict_to_project!
      return if pending?
      project.with_lock do
        case status.to_sym
        when :approved
          project.update!(hardware_stage: "build")
          accrue_discount_for_owner!
        when :returned
          # owner is notified; no project change
        end
      end
    end

    # Flat per-tier discount toward the Outpost Ticket, cumulative on the owner.
    # Snapshotted into discount_stardust_awarded so re-saving an approved request
    # never double-accrues.
    def accrue_discount_for_owner!
      return unless approved?
      return if discount_stardust_awarded.present?

      awarded = tier_discount_stardust

      owner = project.memberships.owner.first&.user || user
      owner.with_lock do
        owner.update!(outpost_discount_stardust: owner.outpost_discount_stardust + awarded)
      end
      update_column(:discount_stardust_awarded, awarded)
    end

    def notify_owner!
      owner = project.memberships.owner.first&.user
      return unless owner&.slack_id.present?

      case status.to_sym
      when :approved
        owner.dm_user("Your hardware project '#{project.title}' was approved for $#{final_amount_dollars} in funding! It's switched to the build phase. Log your build hours with a timelapse and ship when you're ready.")
      when :returned
        msg = "Your funding request for '#{project.title}' needs changes before it can be approved."
        msg += "\n\n#{feedback}" if feedback.present?
        owner.dm_user(msg)
      end
    end
  end
end
