require "test_helper"

# The supplier's order number and the carrier's tracking number are different
# things: only the latter lets a buyer follow the parcel, so fulfilment must be
# able to record it without conflating the two.
class ShopOrderFulfillmentTest < ActiveSupport::TestCase
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    user = create_user(slack_id: "u-fulfil", display_name: "fulfilbuyer", verified: true)
    user.update!(has_gotten_free_stickers: true)

    item = ShopItem.new(
      name: "Fulfilment Patch", description: "A physical item",
      ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!

    @order = user.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: { "country" => "US", "primary" => true })
    @order.update_columns(aasm_state: "awaiting_periodical_fulfillment")
  end

  test "mark_fulfilled records a tracking number separately from the supplier order ref" do
    @order.mark_fulfilled!("WiMo #20162818", 12.5, "a fulfiller", "1Z999AA10123456784")

    @order.reload
    assert_predicate @order, :fulfilled?
    assert_equal "WiMo #20162818", @order.external_ref
    assert_equal "1Z999AA10123456784", @order.tracking_number
  end

  test "mark_fulfilled leaves an existing tracking number alone when none is given" do
    @order.update_columns(tracking_number: "pkg!already-known")

    @order.mark_fulfilled!("WiMo #20162818", nil, "a fulfiller")

    assert_equal "pkg!already-known", @order.reload.tracking_number
  end
end
