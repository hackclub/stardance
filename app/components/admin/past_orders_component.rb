module Admin
  class PastOrdersComponent < ViewComponent::Base
    attr_reader :user, :orders, :title, :collapsible

    def initialize(user:, orders: nil, title: "Past Orders", collapsible: true)
      @user = user
      @orders = orders || user.shop_orders.includes(:shop_item).order(created_at: :desc)
      @title = title
      @collapsible = collapsible
    end

    def render?
      orders.any?
    end

    def display_state(order)
      if order.on_hold? && helpers.current_user.has_role?(:helper) && !helpers.current_user.admin?
        "Pending"
      else
        order.aasm_state.humanize
      end
    end
  end
end
