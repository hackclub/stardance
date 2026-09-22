require "test_helper"

module Admin
  module MegaDashboard
    # Sticky Streak stickers are earned a day at a time and clear review
    # unattended, so a single 21 day run adds 21 orders nobody worked. The
    # dashboard leaves them out of every shop number it reports.
    class StreakStickerExclusionTest < ActiveSupport::TestCase
      include UserFactory

      PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

      setup do
        @user = create_user(slack_id: "u-streak-stats", display_name: "streakbuyer", verified: true)
        @user.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate
        @address = { "country" => "US", "phone_number" => "+15555550123", "primary" => true }

        @patch = place_order(build_item)
        @sticker = place_order(build_item(type: "ShopItem::StickyStreakSticker"))
      end

      test "streak stickers stay out of the fraud queue" do
        pending = Queue.find("fraud_orders").pending.call

        assert_includes pending, @patch
        assert_not_includes pending, @sticker
      end

      test "streak stickers stay out of the fulfillment queue" do
        await_fulfillment

        pending = Queue.find("shop_fulfillment").pending.call

        assert_includes pending, @patch
        assert_not_includes pending, @sticker
      end

      test "streak stickers stay out of the fulfillment mix" do
        await_fulfillment

        groups = FulfillmentStats.new.to_h[:groups]

        assert_equal 1, groups.find { |group| group[:label] == "All" }[:awaiting]
        assert_nil groups.find { |group| group[:label] == "Sticky streak sticker" }
      end

      private

      def await_fulfillment
        [ @patch, @sticker ].each { |order| order.update!(aasm_state: "awaiting_periodical_fulfillment") }
      end

      def build_item(type: "ShopItem::ThirdPartyPhysical")
        item = ShopItem.new(
          name: "Test item #{SecureRandom.hex(4)}",
          description: "A cheap physical item",
          ticket_cost: 0,
          usd_cost: 7,
          type: type,
          enabled: true,
          mission_prize_only: false
        )
        item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
        item.save!
        item
      end

      # Left in review deliberately: performing the enqueued job would clear the
      # sticker by item type, which is the behaviour the queue is meant to omit.
      def place_order(item)
        @user.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: @address)
      end
    end
  end
end
