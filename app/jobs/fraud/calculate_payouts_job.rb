# frozen_string_literal: true

class Fraud::CalculatePayoutsJob < ApplicationJob
  queue_as :literally_whenever

  def perform(triggered_by: nil)
    review_payouts = FraudReviewPayout.payable.to_a
    return if review_payouts.empty?

    run = FraudPayoutRun.new(
      period_start: last_run_end,
      period_end: Time.current,
      total_orders: 0,
      total_amount: 0
    )

    FraudPayoutRun.transaction do
      run.save!

      total = pay_out_reviews(run, review_payouts)

      run.update!(
        total_orders: review_payouts.sum(&:item_count),
        total_amount: total,
        approved_by_user: triggered_by
      )

      run.approve!
      run.log_approval!(by: triggered_by)
    end
  end

  private

  # One line per reviewer: their amount is already fixed by the per-person
  # formula, so nothing is shared out between them.
  def pay_out_reviews(run, review_payouts)
    review_payouts.group_by(&:reviewer_id).sum do |reviewer_id, payouts|
      amount = payouts.sum(&:credited_amount)

      line = run.lines.create!(
        user_id: reviewer_id,
        order_count: payouts.sum(&:item_count),
        amount: amount
      )
      FraudReviewPayout.where(id: payouts.map(&:id)).update_all(fraud_payout_line_id: line.id)

      amount
    end
  end

  def last_run_end
    FraudPayoutRun.order(period_end: :desc).pick(:period_end)
  end
end
