# frozen_string_literal: true

class Shop::ProcessWarehouseOrdersJob < ApplicationJob
  queue_as :literally_whenever
  def perform
    warehouse_orders = ShopOrder
      .joins(:shop_item)
      .where(shop_items: { type: %w[ShopItem::WarehouseItem] }).where(aasm_state: "awaiting_periodical_fulfillment", warehouse_package_id: nil)

    return if warehouse_orders.empty?

    grouped_orders = warehouse_orders.group_by do |order|
      [ order.user_id, order.frozen_address ]
    end

    grouped_orders.each do |(user_id, frozen_address), orders|
      process_coalesced_orders(orders, user_id, frozen_address)
    end
  end

  private

  def process_coalesced_orders(orders, user_id, frozen_address)
    unless frozen_address&.dig("phone_number").present?
      Rails.logger.warn "Skipping warehouse package for user #{user_id}: no phone number on file for this address"
      return
    end

    warehouse_pkg = nil

    ShopWarehousePackage.transaction do
      warehouse_pkg = ShopWarehousePackage.create!(
        user_id: user_id,
        frozen_address: frozen_address
      )

      orders.each do |order|
        order.update!(
          warehouse_package: warehouse_pkg,
          aasm_state: order.aasm_state
        )
      end

      warehouse_pkg.send_to_theseus!
    end

    orders.each do |order|
      order.mark_fulfilled!(warehouse_pkg.theseus_package_id, nil, "System - Warehouse Package")
    end
  end
end
