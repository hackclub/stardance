# frozen_string_literal: true

class Shop::RetryFreeStickerOrdersJob < ApplicationJob
  queue_as :default

  def perform
    orders = ShopOrder.where(aasm_state: "pending")
                      .joins("INNER JOIN shop_items ON shop_items.id = shop_orders.shop_item_id")
                      .where(shop_items: { type: "ShopItem::FreeStickers" })

    orders.find_each do |order|
      order.shop_item.fulfill!(order)
      order.mark_stickers_received
    rescue StandardError => e
      Rails.logger.error "RetryFreeStickerOrdersJob: failed to fulfill order #{order.id}: #{e.message}"
      Sentry.capture_exception(e, extra: { order_id: order.id, user_id: order.user_id })
    end
  end
end
