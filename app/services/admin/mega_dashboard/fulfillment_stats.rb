module Admin
  module MegaDashboard
    # What is sitting in fulfillment, grouped the way the fulfillment team
    # actually splits the work rather than by raw item class.
    class FulfillmentStats
      # Warehouse orders older than this are the ones that quietly rot.
      STALE_WAREHOUSE_DAYS = 3
      RECENT_ITEM_LIMIT = 12

      def initialize(now: Time.current)
        @now = now
      end

      def to_h
        awaiting = countable.where(aasm_state: "awaiting_periodical_fulfillment").group("shop_items.type").count
        fulfilled = countable.where(aasm_state: "fulfilled").group("shop_items.type").count

        {
          groups: build_rows(awaiting, fulfilled),
          stale_warehouse: stale_warehouse_count,
          stale_days: STALE_WAREHOUSE_DAYS,
          recent_items: ::ShopItem.recently_added.enabled.limit(RECENT_ITEM_LIMIT).pluck(:name)
        }
      end

      private

      # Both giveaways are left out: free stickers and Sticky Streak stickers
      # arrive in bulk and would bury the items the team actually packs.
      def countable = ::ShopOrder.real.without_streak_stickers

      # One row per item type, biggest queue first, so nothing hides in a
      # catch-all bucket.
      def build_rows(awaiting, fulfilled)
        rows = (awaiting.keys | fulfilled.keys).map do |type|
          { label: type.to_s.demodulize.underscore.humanize, awaiting: awaiting.fetch(type, 0), fulfilled: fulfilled.fetch(type, 0) }
        end
        rows = rows.sort_by { |row| [ -row[:awaiting], -row[:fulfilled] ] }
        rows << { label: "All", awaiting: awaiting.values.sum, fulfilled: fulfilled.values.sum }
      end

      def stale_warehouse_count
        ::ShopOrder.joins(:shop_item)
                   .where(aasm_state: "awaiting_periodical_fulfillment")
                   .where(shop_items: { type: "ShopItem::WarehouseItem" })
                   .where("shop_orders.awaiting_periodical_fulfillment_at <= ?", STALE_WAREHOUSE_DAYS.days.ago)
                   .count
      end
    end
  end
end
