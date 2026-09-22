require "test_helper"

# Banning has to clear every order the user still has in flight. Held and
# awaiting-verification orders used to survive the ban and sit in the fraud
# queue forever, since nothing else ever revisits them.
class User::ModerationTest < ActiveSupport::TestCase
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @user = create_user(slack_id: "u-banned", display_name: "banme", verified: true)
    @user.update!(has_gotten_free_stickers: true)
    @item = build_item
  end

  test "banning rejects orders in every state a rejection can reach" do
    orders = ShopOrder::REJECTABLE_STATES.index_with { |state| place_order(state) }

    @user.ban!(reason: "test")

    orders.each do |state, order|
      assert_equal "rejected", order.reload.aasm_state, "order left in #{state} after ban"
      assert_equal "test", order.rejection_reason
    end
  end

  test "banning leaves settled orders alone" do
    fulfilled = place_order("fulfilled")

    @user.ban!(reason: "test")

    assert_equal "fulfilled", fulfilled.reload.aasm_state
  end

  private

  def place_order(state)
    order = @user.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: { "country" => "US" })
    order.update_column(:aasm_state, state)
    order
  end

  def build_item
    item = ShopItem.new(
      name: "Test Patch #{SecureRandom.hex(4)}",
      description: "A cheap physical item",
      ticket_cost: 0,
      usd_cost: 7,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
