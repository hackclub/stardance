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

    orders
      .group_by { |order| reviewer_by_order_id[order.id] }
      .reject { |reviewer_id, _| reviewer_id.nil? }
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

  private

  def distribute_payouts!
    lines.includes(:user).find_each do |line|
      line.user.ledger_entries.create!(
        amount: line.amount,
        reason: "Fraud squad payout for #{line.order_count} #{'order'.pluralize(line.order_count)} reviewed",
        created_by: "System",
        ledgerable: line
      )
    end
  end

  def release_orders!
    ShopOrder.where(fraud_payout_line: lines).update_all(fraud_payout_line_id: nil)
  end
end
