# frozen_string_literal: true

class Fraud::CalculatePayoutsJob < ApplicationJob
  queue_as :default

  def perform(manual: false)
    orders = eligible_orders(manual)
    return if orders.empty?

    now = Time.current

    run = FraudPayoutRun.new(
      period_start: manual ? last_run_end : nil,
      period_end: now,
      total_orders: 0,
      total_amount: 0
    )

    grouped = orders.group_by { |o| reviewer_id_for(o) }.reject { |uid, _| uid.nil? }

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

  def eligible_orders(manual)
    scope = ShopOrder
      .where(aasm_state: FraudPayoutRun::REVIEW_STATES)
      .where(fraud_payout_line_id: nil)

    scope = scope.where("shop_orders.created_at >= ?", last_run_end) if manual && last_run_end
    scope.to_a
  end

  def reviewer_id_for(order)
    FraudPayoutRun.reviewer_versions
      .where(item_id: order.id)
      .order(:created_at)
      .filter_map { |v| FraudPayoutRun.reviewer_from_version(v) }
      .first
  end

  def last_run_end
    @last_run_end ||= FraudPayoutRun.order(period_end: :desc).pick(:period_end)
  end
end
