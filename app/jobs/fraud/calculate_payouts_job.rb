# frozen_string_literal: true

class Fraud::CalculatePayoutsJob < ApplicationJob
  queue_as :literally_whenever

  def perform(manual: false)
    orders = eligible_orders(manual)
    review_payouts = FraudReviewPayout.payable.to_a
    return if orders.empty? && review_payouts.empty?

    now = Time.current

    run = FraudPayoutRun.new(
      period_start: manual ? last_run_end : nil,
      period_end: now,
      total_orders: 0,
      total_amount: 0
    )

    grouped = FraudPayoutRun.orders_by_reviewer(orders)

    leaderboard = grouped.map { |user_id, user_orders| { user: user_id, total: user_orders.size } }
    bracket_results = BracketCalculator.new(leaderboard, 1000).calculate
    payouts_by_user = bracket_results[:results].index_by { |r| r[:user] }

    FraudPayoutRun.transaction do
      run.save!

      grouped.each do |user_id, user_orders|
        order_count = user_orders.size
        amount = payouts_by_user[user_id]&.fetch(:payout, 0).to_i

        line = run.lines.create!(
          user_id: user_id,
          order_count: order_count,
          amount: amount
        )

        ShopOrder.where(id: user_orders.map(&:id)).update_all(fraud_payout_line_id: line.id)
      end

      review_total = pay_out_reviews(run, review_payouts)

      run.update!(
        total_orders: orders.size + review_payouts.sum(&:item_count),
        total_amount: bracket_results[:total_distributed].to_i + review_total
      )

      run.approve!
    end
  end

  private

  # Per-person review payouts get their own line per reviewer: their amount is
  # already fixed by the formula, so they do not go through the bracket split
  # that shares out the per-order pot.
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

  def eligible_orders(manual)
    scope = FraudPayoutRun.payout_eligible_orders

    scope = scope.where("shop_orders.created_at >= ?", last_run_end) if manual && last_run_end
    scope.to_a
  end

  def last_run_end
    @last_run_end ||= FraudPayoutRun.order(period_end: :desc).pick(:period_end)
  end
end
