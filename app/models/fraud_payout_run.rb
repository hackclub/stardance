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
      after { release_payouts! }
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

  def release_payouts!
    FraudReviewPayout.where(fraud_payout_line: lines).update_all(fraud_payout_line_id: nil)
  end
end
