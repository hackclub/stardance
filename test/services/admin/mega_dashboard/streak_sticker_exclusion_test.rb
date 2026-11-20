require "test_helper"

module Admin
  module MegaDashboard
    # Sticky Streak stickers are earned a day at a time and clear review
    # unattended, so a single 21 day run adds 21 orders nobody worked. The
    # hand-fulfilled numbers leave them out; the lettermail section counts them.
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

      test "streak stickers stay out of the fraud queue's history" do
        pairs = Queue.find("fraud_queue").timestamp_pairs(1.day.ago)

        assert_equal [ [ @patch.created_at.to_i, nil ] ], pairs.map { |entered, decided| [ entered.to_i, decided ] }
      end

      test "streak stickers stay out of the fulfillment queue" do
        await_fulfillment

        pending = Queue.find("shop_fulfillment").pending.call

        assert_includes pending, @patch
        assert_not_includes pending, @sticker
      end

      test "streak stickers stay out of the hand-fulfilled mix" do
        await_fulfillment

        groups = FulfillmentStats.new.to_h[:groups]

        assert_equal 1, groups.find { |group| group[:label] == "All" }[:awaiting]
        assert_nil groups.find { |group| group[:label] == "Sticky streak sticker" }
      end

      test "streak and free stickers are counted with letter mail" do
        # Skips the "post a devlog first" validation, which has nothing to do with the counts.
        free = @user.shop_orders.new(shop_item: build_item(type: "ShopItem::FreeStickers"), quantity: 1, frozen_address: @address)
        free.save!(validate: false)
        [ @sticker, free ].each { |order| order.update!(aasm_state: "awaiting_periodical_fulfillment") }

        groups = FulfillmentStats.new.to_h[:lettermail_groups]

        assert_equal [ "All", "Free stickers", "Sticky streak sticker" ], groups.map { |group| group[:label] }.sort
        assert_equal 2, groups.find { |group| group[:label] == "All" }[:awaiting]
      end

      test "streak stickers are in the lettermail queue and not the hand-fulfilled one" do
        await_fulfillment

        assert_equal [ @sticker ], Queue.find("lettermail").pending.call.to_a
        assert_equal [ @patch ], Queue.find("shop_fulfillment").pending.call.to_a
      end

      test "letter mail is counted apart from hand-fulfilled orders" do
        letter = place_order(build_item(type: "ShopItem::LetterMail"))
        [ @patch, letter ].each { |order| order.update!(aasm_state: "awaiting_periodical_fulfillment") }

        stats = FulfillmentStats.new.to_h

        assert_equal [ "Letter mail", "All" ], stats[:lettermail_groups].map { |group| group[:label] }
        assert_equal [ 1, 1 ], stats[:lettermail_groups].map { |group| group[:awaiting] }
        assert_equal [ "Third party physical", "All" ], stats[:groups].map { |group| group[:label] }
        assert_equal [ 1, 1 ], stats[:groups].map { |group| group[:awaiting] }
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
