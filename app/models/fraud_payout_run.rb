# frozen_string_literal: true

# == Schema Information
#
# Table name: fraud_payout_runs
#
#  id                  :bigint           not null, primary key
#  aasm_state          :string
#  approved_at         :datetime
#  period_end          :datetime
#  period_start        :datetime
#  total_amount        :integer
#  total_orders        :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  approved_by_user_id :bigint
#
class FraudPayoutRun < ApplicationRecord
  include AASM

  has_paper_trail

  has_many :lines, class_name: "FraudPayoutLine", dependent: :destroy
  belongs_to :approved_by_user, class_name: "User", optional: true

  REVIEW_STATES = %w[awaiting_periodical_fulfillment rejected on_hold].freeze

  def self.payout_eligible_orders
    ShopOrder
      .where(aasm_state: REVIEW_STATES)
      .where(fraud_payout_line_id: nil)
      .where(fraud_review_payout_id: nil)
  end

  # Base scope for PaperTrail versions that could represent a fraud review.
  def self.reviewer_versions
    ::PaperTrail::Version
      .where(item_type: "ShopOrder")
      .where.not(whodunnit: nil)
      .where("object_changes ? 'aasm_state'")
  end

  # Returns the reviewer user ID if the version represents a fraud-review
  # state transition, nil otherwise.
  def self.reviewer_from_version(version)
    changes = version.object_changes
    return nil if changes.is_a?(String) && changes.start_with?("---")
    changes = JSON.parse(changes) if changes.is_a?(String)
    state_change = changes["aasm_state"]
    return nil unless state_change.is_a?(Array) && state_change[1].in?(REVIEW_STATES)
    # whodunnit is not always a user id: jobs and console scripts stamp their
    # own name, and auto-approval settles a review state under
    # "Shop::AutoApprovable". Those reviews were nobody's work to pay for.
    return nil unless version.whodunnit.match?(/\A\d+\z/)

    version.whodunnit.to_i
  end

  def self.orders_by_reviewer(orders)
    orders = orders.to_a
    reviewer_by_order_id = {}

    reviewer_versions
      .where(item_id: orders.map(&:id))
      .order(:created_at, :id)
      .each do |version|
        reviewer_id = reviewer_from_version(version)
        reviewer_by_order_id[version.item_id.to_i] ||= reviewer_id if reviewer_id
      end

    # A reviewer id that no longer names a user cannot be paid, and a line
    # pointing at one fails the run's foreign key, which rolls back the whole
    # month rather than the one line nobody could be paid for.
    payable = User.where(id: reviewer_by_order_id.values.uniq).pluck(:id).to_set

    orders
      .group_by { |order| reviewer_by_order_id[order.id] }
      .select { |reviewer_id, _| payable.include?(reviewer_id) }
  end

  aasm timestamps: true do
    state :pending_approval, initial: true
    state :approved
    state :rejected

    event :approve do
      transitions from: :pending_approval, to: :approved
      after { distribute_payouts! }
    end

    event :reject do
      transitions from: :pending_approval, to: :rejected
      after { release_orders! }
    end
  end

  # Logged as its own event rather than leaning on the update version: a run
  # that approves itself at the end of a calculation has no controller around
  # to set whodunnit.
  def log_approval!(by:)
    ::PaperTrail::Version.create!(
      item_type: "FraudPayoutRun",
      item_id: id,
      event: "approved",
      whodunnit: by&.id.to_s,
      object_changes: { aasm_state: %w[pending_approval approved] }.to_json
    )
  end

  private

  def distribute_payouts!
    lines.includes(:user).find_each do |line|
      line.user.ledger_entries.create!(
        amount: line.amount,
        reason: line.payout_reason,
        created_by: "System",
        ledgerable: line
      )
    end
  end

  def release_orders!
    ShopOrder.where(fraud_payout_line: lines).update_all(fraud_payout_line_id: nil)
    FraudReviewPayout.where(fraud_payout_line: lines).update_all(fraud_payout_line_id: nil)
  end
end
