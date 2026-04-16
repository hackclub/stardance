# frozen_string_literal: true

class Shop::ProcessLetterMailOrdersJob < ApplicationJob
  queue_as :default

  def perform
    orders = ShopOrder.joins(:shop_item)
                      .where(shop_items: { type: "ShopItem::LetterMail" })
                      .where(aasm_state: "awaiting_periodical_fulfillment")

    return if orders.empty?

    grouped_orders = orders.group_by { |order| [ order.user_id, order.frozen_address ] }

    grouped_orders.each do |(user_id, frozen_address), coalesced_orders|
      process_coalesced_orders(coalesced_orders)
    rescue => e
      Rails.logger.error("Failed to process letter mail orders #{coalesced_orders.map(&:id)}: #{e.message}")
    end
  end

  private

  def process_coalesced_orders(orders)
    letter_id = TheseusService.create_letter(orders, queue: "stardance-envelope")

    orders.each do |order|
      order.mark_fulfilled!(letter_id, nil, "System - Letter Mail")
    end
  end
end
