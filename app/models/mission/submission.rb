# == Schema Information
#
# Table name: mission_submissions
#
#  id                               :bigint           not null, primary key
#  claim_expires_at                 :datetime
#  claimed_at                       :datetime
#  deleted_at                       :datetime
#  payout_path                      :string           not null
#  pending_at                       :datetime
#  rejection_message                :text
#  reviewed_at                      :datetime
#  status                           :string           not null
#  submission_guide_acknowledged_at :datetime
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  chosen_prize_id                  :bigint
#  mission_id                       :bigint           not null
#  reviewed_by_id                   :bigint
#  ship_event_id                    :bigint           not null
#  shop_order_id                    :bigint
#
# Indexes
#
#  idx_mission_submissions_on_status_claim_expires     (status,claim_expires_at)
#  index_mission_submissions_active_per_ship_event     (ship_event_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_mission_submissions_on_chosen_prize_id        (chosen_prize_id)
#  index_mission_submissions_on_deleted_at             (deleted_at)
#  index_mission_submissions_on_mission_id             (mission_id)
#  index_mission_submissions_on_mission_id_and_status  (mission_id,status)
#  index_mission_submissions_on_reviewed_by_id         (reviewed_by_id)
#  index_mission_submissions_on_ship_event_id          (ship_event_id)
#  index_mission_submissions_on_shop_order_id          (shop_order_id)
#  index_mission_submissions_on_status_and_created_at  (status,created_at)
#  index_mission_submissions_on_status_and_pending_at  (status,pending_at)
#  index_mission_submissions_with_shop_order           (shop_order_id) WHERE (shop_order_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (chosen_prize_id => mission_prizes.id)
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (reviewed_by_id => users.id)
#  fk_rails_...  (ship_event_id => post_ship_events.id)
#  fk_rails_...  (shop_order_id => shop_orders.id)
#
class Mission::Submission < ApplicationRecord
  self.table_name = "mission_submissions"

  include SoftDeletable
  include Ledgerable
  include AASM
  include MissionReviewable
  include Mission::PrizeRedeemable

  has_paper_trail

  belongs_to :ship_event,    class_name: "Post::ShipEvent",  inverse_of: :mission_submission
  belongs_to :mission,       inverse_of: :submissions
  belongs_to :reviewed_by,   class_name: "User",             optional: true
  belongs_to :chosen_prize,  class_name: "Mission::Prize",   optional: true
  belongs_to :shop_order,                                    optional: true

  PAYOUT_PATHS = %w[static_prize voting].freeze

  validates :payout_path, presence: true, inclusion: { in: PAYOUT_PATHS }
  validates :ship_event_id, uniqueness: { conditions: -> { where(deleted_at: nil) } }

  aasm column: :status, no_direct_assignment: true do
    state :awaiting_certification, initial: true
    # Queue age counts from the last review, so entering the queue (ship cert
    # approved, or a decision undone/resubmitted) restamps pending_at.
    state :pending, before_enter: :stamp_pending_at
    state :approved
    state :rejected

    # System: ship cert resolved.
    event :certify, after: :notify_reviewers do
      transitions from: :awaiting_certification, to: :pending
    end

    event :fail_certification do
      transitions from: :awaiting_certification, to: :rejected
    end

    # Reviewer.
    event :approve do
      transitions from: :pending, to: :approved
    end

    event :reject do
      transitions from: :pending, to: :rejected
    end

    # Admin override.
    event :undo do
      transitions from: [ :approved, :rejected ], to: :pending
    end
  end

  # "Shipped" in the loose sense: any submission still in flight or approved.
  # Contrast with `approved` for sites that need full completion.
  scope :not_rejected, -> { where.not(status: "rejected") }
  # Still working its way through certification/review.
  scope :in_review, -> { where.not(status: %w[approved rejected]) }

  scope :reviewable,  -> { pending }
  # What the review overview queues. Hardware missions are reviewed as funding
  # requests and ship certs on their projects instead, and an
  # awaiting_certification submission has no pending_at because it has not
  # entered the queue yet. `hardware` is nullable in practice despite the
  # annotation, and a null mission is a software one.
  scope :software_reviewable, -> {
    joins(:mission)
      .where(deleted_at: nil, missions: { enabled: true, hardware: [ false, nil ] })
      .where.not(status: "awaiting_certification")
  }
  scope :stale_pending, ->(days: 7) {
    pending.where("pending_at < ?", days.days.ago)
  }
  # Every verdict handed down on a project, across every mission it has been
  # submitted to, newest first. Includes verdicts since erased from the record
  # by a re-review request, so see Verdict before relying on the columns alone.
  def self.review_history_for(project, excluding: nil)
    Verdict.history_for(project, excluding: excluding)
  end

  # When the submission last entered the review queue; created_at covers rows
  # that predate pending_at (or never reached the queue).
  def queue_entered_at
    pending_at || created_at
  end

  # Redemption-gate interface (see Mission::PrizeRedeemable): an approved
  # submission claims the mission's after-shipping prizes.
  def redemption_mission = mission
  def redemption_prize_category = :after_shipping

  # Rewards granted when a submission is approved: the mission achievement and
  # any fixed stardust. Idempotent. reviewer_id is recorded on the ledger entry.
  def grant_rewards!(reviewer_id:)
    grant_mission_achievement
    grant_fixed_stardust(reviewer_id: reviewer_id)
  end

  # Undoes grant_rewards! when a decision is reversed.
  def reverse_rewards!(reviewer_id:)
    reverse_fixed_stardust(reviewer_id: reviewer_id)
    revoke_mission_achievement
  end

  # Per-mission reviewers/owners, minus teammates (no self-review). Global
  # mission_reviewers manage every mission but are deliberately left out here —
  # they opt into the queue rather than being paged for each submission.
  def reviewer_recipients
    teammate_ids = ship_event&.post&.project&.users&.pluck(:id) || []

    per_mission_ids = mission.memberships.pluck(:user_id)

    User.where(id: per_mission_ids.uniq - teammate_ids)
        .where.not(slack_id: [ nil, "" ])
  end

  def notification_locals
    project = ship_event&.post&.project
    builder = ship_event&.post&.user
    routes = Rails.application.routes.url_helpers
    url_opts = (Rails.application.config.action_controller.default_url_options || {})
                    .reverse_merge(host: "stardance.hackclub.com", protocol: "https")

    {
      mission_name: mission.name,
      mission_url: routes.mission_url(mission.slug, **url_opts),
      project_title: project&.title || "Unknown project",
      project_url: project ? routes.project_url(project, **url_opts) : routes.root_url(**url_opts),
      builder_name: builder&.display_name || "the builder",
      payout_path: payout_path.titleize,
      admin_submission_url: routes.admin_mission_submission_url(mission.slug, self, **url_opts),
      redeem_url: mission.prizes_count > 0 ? routes.redeem_mission_submission_url(self, **url_opts) : nil,
      rejection_message: rejection_message.to_s
    }
  end

  private

  def reward_recipient
    ship_event&.post&.user
  end

  def grant_mission_achievement
    return if mission.achievement_slug.blank?
    return unless reward_recipient
    return if reward_recipient.achievements.exists?(achievement_slug: mission.achievement_slug)

    reward_recipient.achievements.create!(achievement_slug: mission.achievement_slug, earned_at: Time.current)
  end

  def grant_fixed_stardust(reviewer_id:)
    return unless mission.fixed_stardust_payout&.positive?
    return unless ledger_entries.sum(:amount).zero?
    return unless reward_recipient

    ledger_entries.create!(
      user: reward_recipient,
      amount: mission.fixed_stardust_payout,
      reason: "Mission: #{mission.name}",
      created_by: "mission_submission:#{id} (#{reviewer_id})"
    )
  end

  def reverse_fixed_stardust(reviewer_id:)
    net = ledger_entries.sum(:amount)
    return unless net.positive?
    return unless reward_recipient

    ledger_entries.create!(
      user: reward_recipient,
      amount: -net,
      reason: "Mission reversal: #{mission.name}",
      created_by: "mission_submission:#{id} undo (#{reviewer_id})"
    )
  end

  def revoke_mission_achievement
    return if mission.achievement_slug.blank?
    return unless reward_recipient

    reward_recipient.achievements.where(achievement_slug: mission.achievement_slug).destroy_all
  end

  def stamp_pending_at
    self.pending_at = Time.current
  end

  def notify_reviewers
    builder = ship_event&.post&.user
    reviewer_recipients.find_each do |reviewer|
      Notifications::Missions::SubmissionPendingForReviewer.notify(recipient: reviewer, actor: builder, record: self)
    end
  rescue StandardError => e
    Rails.logger.warn("Mission::Submission notify_reviewers (#{id}): #{e.message}")
  end
end
