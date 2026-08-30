# frozen_string_literal: true

class Shop::ProcessVerifiedOrdersJob < ApplicationJob
  queue_as :latency_5m

  def perform(user_id)
    user = User.find(user_id)
    return unless user.eligible_for_shop?

    orders = user.shop_orders.where(aasm_state: "awaiting_verification")
    orders.find_each do |order|
      begin
        if order.shop_item.is_a?(ShopItem::FreeStickers)
          order.shop_item.fulfill!(order)
          order.mark_stickers_received
        else
          order.update!(aasm_state: "pending")
        end
      rescue StandardError => e
        Rails.logger.error "Failed to process order #{order.id} for user #{user_id}: #{e.message}"
        Sentry.capture_exception(e, extra: { order_id: order.id, user_id: user_id })
        next
      end
    end
  end
end
