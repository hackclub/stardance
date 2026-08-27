# frozen_string_literal: true

class Shop::ProcessLetterMailOrdersJob < ApplicationJob
  queue_as :default

  LETTER_TYPES = ShopItem::LetterMail::BULK_BATCHED_TYPES

  def perform
    orders = ShopOrder.joins(:shop_item)
                      .where(shop_items: { type: LETTER_TYPES })
                      .where(aasm_state: "awaiting_periodical_fulfillment")
                      .includes(:shop_item, :user)
                      .order(:id) # deterministic chunks on retry, so the idempotency key dedupes

    return if orders.empty?

    grouped_orders = orders.group_by { |order| [ order.user_id, order.frozen_address, order.shop_item.type ] }

    grouped_orders.each_value do |group|
      # Same lock format as individual send_to_theseus runs
      user = group.first.user
      user.with_advisory_lock("theseus_send/#{user.id}", timeout_seconds: 10) do
        # reload to prevent a race or double send
        sendable = group.select { |order| order.reload.awaiting_periodical_fulfillment? }
        next if sendable.empty?

        cap = sendable.first.shop_item.class::MAX_ITEMS_PER_LETTER
        chunk_by_quantity(sendable, cap).each do |letter_orders|
          process_coalesced_orders(letter_orders)
        end
      end
    rescue => e
      Rails.logger.error("Failed to process letter mail orders #{group.map(&:id)}: #{e.message}")
    end
  end

  private

  def chunk_by_quantity(orders, cap)
    chunks = []
    current = []
    quantity = 0

    orders.each do |order|
      if current.any? && quantity + order.quantity > cap
        chunks << current
        current = []
        quantity = 0
      end
      current << order
      quantity += order.quantity
    end

    chunks << current if current.any?
    chunks
  end

  def process_coalesced_orders(orders)
    queue = orders.first.shop_item.class::THESEUS_QUEUE
    letter_id = TheseusService.create_letter(orders, queue: queue)

    orders.each do |order|
      order.mark_fulfilled!(letter_id, nil, "System - Letter Mail")
    end
  end
end
