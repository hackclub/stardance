require "test_helper"

# The buyer's order list shows carrier tracking on its own line, linked to the
# carrier, separately from the store order reference in external_ref.
class ShopOrdersTrackingTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    item = ShopItem.new(
      name: "Tracked Sticker", description: "A physical item",
      ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!

    @buyer = create_user(slack_id: "U_TRO_BUYER", display_name: "tro_buyer", verified: true)
    @buyer.update!(has_gotten_free_stickers: true)
    @order = @buyer.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: { "country" => "GB", "primary" => true })
    @order.update_columns(aasm_state: "fulfilled", external_ref: "ORD-12345", tracking_number: "AB123456789GB")
  end

  test "the orders page links the tracking and still shows the external ref" do
    sign_in @buyer
    get shop_orders_path

    assert_response :success
    assert_select ".my-orders__status-hint--tracking a[href=?]",
                  "https://www.royalmail.com/track-your-item#/tracking-results/AB123456789GB", text: "AB123456789GB"
    assert_select ".my-orders__status-hint", text: /ORD-12345/
  end

  test "no tracking line until tracking is set" do
    @order.update_columns(tracking_number: nil)

    sign_in @buyer
    get shop_orders_path

    assert_select ".my-orders__status-hint--tracking", 0
  end
end
