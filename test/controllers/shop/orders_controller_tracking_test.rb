require "test_helper"

# Regression coverage for a support ticket: the buyer's orders page showed the
# supplier's order number ("WiMo #20162818") after "You can track the package
# here", so buyers tried to track with it. Only a real tracking number (or a
# Hack Club mail id) is presented as tracking; a supplier reference is always
# labelled as an order reference.
class Shop::OrdersControllerTrackingTest < ActionDispatch::IntegrationTest
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @user = create_user(slack_id: "U-tracking", display_name: "trackbuyer", verified: true)
    @user.update!(has_gotten_free_stickers: true)

    item = ShopItem.new(
      name: "Tracked Patch", description: "A physical item",
      ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!

    @order = @user.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: { "country" => "US", "primary" => true })
    @order.update_columns(aasm_state: "fulfilled")
    sign_in @user
  end

  test "a supplier order number is not presented as tracking" do
    @order.update_columns(external_ref: "WiMo #20162818")

    get shop_orders_path

    assert_response :success
    assert_includes hint, "Order reference: WiMo #20162818"
    assert_not_includes hint, "track the package"
  end

  test "a tracking number is shown as the tracking number" do
    @order.update_columns(external_ref: "WiMo #20162818", tracking_number: "1Z999AA10123456784")

    get shop_orders_path

    assert_includes hint, "You can track the package here: 1Z999AA10123456784"
    assert_includes hint, "Order reference: WiMo #20162818"
    assert_not_includes hint, "track the package here: WiMo"
  end

  test "a Theseus reference still links to mail.hackclub.com" do
    @order.update_columns(external_ref: "pkg!abc123")

    get shop_orders_path

    assert_select ".my-orders__status-hint a[href=?]", "https://mail.hackclub.com/pkg!abc123", text: "pkg!abc123"
    assert_includes hint, "track the package"
  end

  test "an order with no reference at all mentions neither" do
    get shop_orders_path

    assert_not_includes hint, "track the package"
    assert_not_includes hint, "Order reference"
  end

  private

  def hint
    css_select(".my-orders__status-hint").map(&:text).join(" ").squish
  end
end
