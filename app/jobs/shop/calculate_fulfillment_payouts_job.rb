# frozen_string_literal: true

class Shop::CalculateFulfillmentPayoutsJob < ApplicationJob
  queue_as :literally_whenever

  def perform(manual: false)
    orders = eligible_orders(manual)
    return if orders.empty?

    now = Time.current

    run = FulfillmentPayoutRun.new(
      period_start: manual ? last_run_end : nil,
      period_end: now,
      total_orders: 0,
      total_amount: 0
    )

    grouped = orders.group_by(&:assigned_to_user_id)

    FulfillmentPayoutRun.transaction do
      run.save!

      grouped.each do |user_id, user_orders|
        order_count = user_orders.size
        amount = order_count * FulfillmentPayoutRun::TICKETS_PER_ORDER

        line = run.lines.create!(
          user_id: user_id,
          order_count: order_count,
          amount: amount
        )

        ShopOrder.where(id: user_orders.map(&:id)).update_all(fulfillment_payout_line_id: line.id)
      end

      run.update!(
        total_orders: orders.size,
        total_amount: grouped.sum { |_, user_orders| user_orders.size * FulfillmentPayoutRun::TICKETS_PER_ORDER }
      )
    end
  end

  private

  def eligible_orders(manual)
    scope = ShopOrder
      .where(aasm_state: "fulfilled")
      .where.not(assigned_to_user_id: nil)
      .where(fulfillment_payout_line_id: nil)

    if manual && last_run_end
      scope = scope.where(fulfilled_at: last_run_end..)
    end

    scope.to_a
  end

  def last_run_end
    @last_run_end ||= FulfillmentPayoutRun.order(period_end: :desc).pick(:period_end)
  end
end
