# frozen_string_literal: true

class Shop::UpdatePostageCostsJob < ApplicationJob
  queue_as :default

  def perform
    orders = ShopOrder.joins(:shop_item)
                      .where(shop_items: { type: ShopItem::LetterMail::TYPES })
                      .where(aasm_state: "fulfilled")
                      .where(fulfillment_cost: nil)
                      .where.not(external_ref: nil)

    orders.each do |order|
      update_postage(order)
    rescue => e
      Rails.logger.error("Failed to update postage for order ##{order.id}: #{e.message}")
    end
  end

  private

  def update_postage(order)
    letter = TheseusService.get_letter(order.external_ref)
    postage = letter[:postage] || letter["postage"]
    return unless postage.present?

    order.update!(fulfillment_cost: postage)
  end
end
