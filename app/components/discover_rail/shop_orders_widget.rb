# frozen_string_literal: true

module DiscoverRail
  class ShopOrdersWidget < BaseWidget
    register_as :shop_orders

    def orders
      context[:sidebar_orders] || []
    end

    def display_state(order)
      order.on_hold? ? "pending" : order.aasm_state
    end

    def render?
      user.present?
    end
  end
end
