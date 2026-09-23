# frozen_string_literal: true

# == Schema Information
#
# Table name: reviewer_payout_requests
#
#  id              :bigint           not null, primary key
#  aasm_state      :string           default("pending"), not null
#  adjust_reason   :text
#  adjusted_amount :integer
#  amount          :integer          not null
#  paid_amount     :integer
#  paid_at         :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  admin_id        :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  index_reviewer_payout_requests_on_admin_id         (admin_id)
#  index_reviewer_payout_requests_on_user_id          (user_id)
#  index_reviewer_payout_requests_on_user_id_pending  (user_id) UNIQUE WHERE ((aasm_state)::text = 'pending'::text)
#
# Foreign Keys
#
#  fk_rails_...  (admin_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
class ReviewerPayoutRequest < ApplicationRecord
  include AASM

  MINIMUM_AMOUNT = 10
  MAX_AMOUNT = 2_147_483_647 # postgres integer column ceiling — hard stop, not a business cap
  HISTORY_LIMIT = 100

  has_paper_trail

  belongs_to :user
  belongs_to :admin, class_name: "User", optional: true

  validates :amount, numericality: { greater_than_or_equal_to: MINIMUM_AMOUNT, less_than_or_equal_to: MAX_AMOUNT, only_integer: true }
  validates :adjusted_amount, numericality: { greater_than: 0, less_than_or_equal_to: MAX_AMOUNT, only_integer: true }, allow_nil: true
  validates :paid_amount, numericality: { greater_than: 0, less_than_or_equal_to: MAX_AMOUNT, only_integer: true }, allow_nil: true
  validates :adjust_reason, presence: { message: "is required when adjusting the amount" },
    if: :adjusted?
  validate :sufficient_balance, on: :create
  validate :no_pending_request, on: :create

  aasm timestamps: true do
    state :pending, initial: true
    state :paid
    state :rejected

    event :pay do
      transitions from: :pending, to: :paid
    end

    event :reject do
      transitions from: :pending, to: :rejected
    end
  end

  def final_amount
    adjusted_amount || amount
  end

  def adjusted?
    adjusted_amount.present? && adjusted_amount != amount
  end

  def pay_out(admin:, adjusted_amount:, adjust_reason:)
    with_lock do
      unless may_pay?
        errors.add(:base, "This request cannot be paid in its current state")
        return false
      end

      self.adjusted_amount = adjusted_amount
      self.adjust_reason = adjust_reason
      self.paid_amount = final_amount
      self.admin = admin
      self.paid_at = Time.current

      return false unless valid?
      return false unless requested_amount_available?

      pay!
      create_payout_ledger_entry!(admin)

      true
    end
  end

  def reject_with_reason(admin:, reason:)
    with_lock do
      unless may_reject?
        errors.add(:base, "This request cannot be rejected in its current state")
        return false
      end

      if reason.blank?
        errors.add(:adjust_reason, "is required when rejecting a payout request")
        return false
      end

      self.admin = admin
      self.adjust_reason = reason

      reject!

      true
    end
  end

  def self.total_earned_for(user)
    return 0 unless user
    ship = Certification::Ship
             .where(reviewer: user)
             .decided
             .sum(:stardust_earned)
    funding = Certification::FundingRequest
                .where(reviewer: user)
                .decided
                .sum(:stardust_earned)
    ship + funding
  end

  def self.unclaimed_for(user)
    return 0 unless user
    [ total_earned_for(user) - settled_for(user), 0 ].max
  end

  def self.pending_for(user)
    return nil unless user
    find_by(user: user, aasm_state: "pending")
  end

  def self.available_to_request_for(user)
    return 0 unless user
    [ unclaimed_for(user) - (pending_for(user)&.amount || 0), 0 ].max
  end

  def self.history_for(user)
    return none unless user
    where(user: user).includes(:admin).order(created_at: :desc).limit(HISTORY_LIMIT)
  end

  def decided_at
    return nil if pending?
    paid_at || updated_at
  end

  def self.settled_for(user)
    return 0 unless user

    # Only the requested claim settles against earned stardust. A reduction still
    # settles the full request (the denied difference isn't reclaimable), and a
    # bonus above the request is a no-strings top-up, so counting the surplus here
    # would silently charge it back to the reviewer's future earnings.
    where(user: user, aasm_state: "paid").sum(:amount)
  end

  private

  def sufficient_balance
    return unless user

    unclaimed = self.class.unclaimed_for(user)
    errors.add(:amount, "exceeds your unclaimed earnings (#{unclaimed} ✦)") if amount.to_i > unclaimed
  end

  def requested_amount_available?
    return true unless user

    unclaimed = self.class.unclaimed_for(user)
    return true if amount.to_i <= unclaimed

    errors.add(:amount, "exceeds the reviewer's unclaimed earnings (#{unclaimed} ✦)")
    false
  end

  def no_pending_request
    return unless user

    if self.class.where(user: user, aasm_state: "pending").exists?
      errors.add(:base, "You already have a pending payout request")
    end
  end

  def create_payout_ledger_entry!(admin)
    user.ledger_entries.create!(
      amount: paid_amount,
      reason: "Shipwrights payout ##{id}",
      created_by: admin ? "#{admin.display_name} (#{admin.id})" : "Shipwrights Dashboard",
      ledgerable: self
    )
  end
end
