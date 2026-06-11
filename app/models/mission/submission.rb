# == Schema Information
#
# Table name: mission_submissions
#
#  id                               :bigint           not null, primary key
#  deleted_at                       :datetime
#  payout_path                      :string           not null
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
#  index_mission_submissions_active_per_ship_event     (ship_event_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_mission_submissions_on_chosen_prize_id        (chosen_prize_id)
#  index_mission_submissions_on_deleted_at             (deleted_at)
#  index_mission_submissions_on_mission_id             (mission_id)
#  index_mission_submissions_on_mission_id_and_status  (mission_id,status)
#  index_mission_submissions_on_reviewed_by_id         (reviewed_by_id)
#  index_mission_submissions_on_ship_event_id          (ship_event_id)
#  index_mission_submissions_on_shop_order_id          (shop_order_id)
#  index_mission_submissions_on_status_and_created_at  (status,created_at)
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
    state :pending
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
  scope :unredeemed,  -> { approved.where(shop_order_id: nil) }
  scope :stale_pending, ->(days: 7) {
    pending.where("created_at < ?", days.days.ago)
  }

  # Per-mission + global reviewers, minus teammates (no self-review).
  def reviewer_recipients
    teammate_ids = ship_event&.post&.project&.users&.pluck(:id) || []

    per_mission_ids = mission.memberships.pluck(:user_id)
    global_ids = User.where("? = ANY (granted_roles)", "mission_reviewer").pluck(:id)

    User.where(id: (per_mission_ids + global_ids).uniq - teammate_ids)
        .where(mission_review_notifications: true)
        .where.not(slack_id: [ nil, "" ])
  end

  def notification_locals
    project = ship_event&.post&.project
    builder = ship_event&.post&.user
    routes = Rails.application.routes.url_helpers
    url_opts = Rails.application.config.action_controller.default_url_options
                    .reverse_merge(host: "stardance.hackclub.com", protocol: "https")

    {
      mission_name: mission.name,
      mission_url: routes.mission_url(mission.slug, **url_opts),
      project_title: project&.title || "Unknown project",
      project_url: project ? routes.project_url(project, **url_opts) : routes.root_url(**url_opts),
      builder_name: builder&.display_name || "the builder",
      payout_path: payout_path.titleize,
      submission_url: routes.mission_submission_url(self, **url_opts),
      rejection_message: rejection_message.to_s
    }
  end

  private

  def notify_reviewers
    reviewer_recipients.find_each do |reviewer|
      SendSlackDmJob.perform_later(
        reviewer.slack_id,
        blocks_path: "notifications/missions/submission_pending_for_reviewer.slack_message",
        locals: notification_locals
      )
    end
  rescue StandardError => e
    Rails.logger.warn("Mission::Submission notify_reviewers (#{id}): #{e.message}")
  end
end
