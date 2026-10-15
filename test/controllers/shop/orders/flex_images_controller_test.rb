require "test_helper"

class Shop::Orders::FlexImagesControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @owner = create_user(slack_id: "u-flex-owner", display_name: "flexowner")
    @owner.update!(has_gotten_free_stickers: true)
    @other = create_user(slack_id: "u-flex-other", display_name: "flexother")

    item = ShopItem.new(
      name: "Hardware Build Fund",
      description: "Flex card test item",
      ticket_cost: 0,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "px.png", content_type: "image/png")
    item.save!

    @order = @owner.shop_orders.new(
      shop_item: item,
      quantity: 1,
      frozen_address: { "country" => "US", "phone_number" => "+15555550123", "primary" => true }
    )
    @order.aasm_state = "pending"
    @order.save!
  end

  teardown do
    Flipper.disable(:sharable_purchase)
  end

  test "returns 404 when the flag is off" do
    sign_in @owner
    get shop_order_flex_image_path(@order)
    assert_response :not_found
  end

  test "owner gets their flex image when the flag is on" do
    Flipper.enable(:sharable_purchase)
    sign_in @owner

    get shop_order_flex_image_path(@order)

    assert_response :success
    assert_equal "image/png", response.media_type
    assert response.body.start_with?("\x89PNG".b), "body must be a PNG"
  end

  test "download param serves the png as an attachment" do
    Flipper.enable(:sharable_purchase)
    sign_in @owner

    get shop_order_flex_image_path(@order, download: 1)

    assert_response :success
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/stardance-order-#{@order.id}\.png/, response.headers["Content-Disposition"])
  end

  test "another user cannot fetch someone else's flex image" do
    Flipper.enable(:sharable_purchase)
    sign_in @other

    get shop_order_flex_image_path(@order)

    assert_response :not_found
  end
end
