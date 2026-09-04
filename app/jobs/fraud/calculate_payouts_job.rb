# frozen_string_literal: true

class Fraud::CalculatePayoutsJob < ApplicationJob
  queue_as :literally_whenever

  # `period_start`/`period_end` scope the run to a specific window (e.g. a
  # past month picked from the admin UI) instead of "everything since the
  # last run." Already-paid orders are still excluded via
  # `payout_eligible_orders`, so re-running an old month never double-pays.
  def perform(manual: false, period_start: nil, period_end: nil)
    orders = eligible_orders(manual: manual, period_start: period_start, period_end: period_end)
    return if orders.empty?

    run = FraudPayoutRun.new(
      period_start: period_start || (manual ? last_run_end : nil),
      period_end: period_end || Time.current,
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

      run.update!(
        total_orders: orders.size,
        total_amount: bracket_results[:total_distributed].to_i
      )

      run.approve!
    end
  end

  private

  def eligible_orders(manual:, period_start:, period_end:)
    scope = FraudPayoutRun.payout_eligible_orders

    if period_start || period_end
      scope = scope.where("shop_orders.created_at >= ?", period_start) if period_start
      scope = scope.where("shop_orders.created_at <= ?", period_end) if period_end
    elsif manual && last_run_end
      scope = scope.where("shop_orders.created_at >= ?", last_run_end)
    end

    scope.to_a
  end

  def last_run_end
    @last_run_end ||= FraudPayoutRun.order(period_end: :desc).pick(:period_end)
  end
end
