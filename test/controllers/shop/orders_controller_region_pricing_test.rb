require "test_helper"

# Regression coverage for a reported bug: a buyer could set their shop-region
# preference to whichever region priced an item lowest, then check out to an
# address in a different (pricier) region. The balance check ran against the
# cheap preferred-region price while the actual charge froze the real
# shipping-region price, so an order could go through and push the buyer's
# stardust balance negative.
class Shop::OrdersControllerRegionPricingTest < ActionDispatch::IntegrationTest
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze
  EU_ADDRESS = { "id" => "addr-eu", "country" => "DE", "primary" => true }.freeze
  IDENTITY = { "addresses" => [ EU_ADDRESS ], "phone_number" => "+15551234567" }.freeze

  setup do
    @user = create_user(slack_id: "U-region-bug", display_name: "regionbuyer", verified: true)
    @user.update!(has_gotten_free_stickers: true, shop_region: "US") # prefers the cheaper region on display
    # EU costs more to ship: usd_offset_eu is well above usd_offset_us.
    @item = build_item(ticket_cost: 100, usd_offset_us: 0, usd_offset_eu: 40)
    sign_in @user
  end

  test "a balance that only covers the preferred region's price is rejected, not charged the real shipping price" do
    grant(150) # enough for the (lower) US price of 100, not the real EU price of 300

    with_address do
      post shop_orders_path, params: { shop_item_id: @item.id, quantity: 1 }
    end

    assert_redirected_to shop_item_path(@item)
    assert_match(/Insufficient balance/, flash[:alert])
    assert_equal 0, ShopOrder.count
    assert_equal 150, @user.reload.balance, "a rejected order must never touch the ledger"
  end

  test "an order that goes through always freezes the shipping region's price, never the preference's" do
    grant(300)

    with_address do
      post shop_orders_path, params: { shop_item_id: @item.id, quantity: 1 }
    end

    order = ShopOrder.sole
    assert_equal "EU", order.region
    assert_equal @item.price_for_region("EU"), order.frozen_item_price
    assert_not_equal @item.price_for_region("US"), order.frozen_item_price
    assert_operator @user.reload.balance, :>=, 0
  end

  test "the model-level balance validation is not a no-op: it rejects a too-expensive order built directly" do
    grant(50)

    order = @user.shop_orders.new(shop_item: @item, quantity: 1, frozen_address: EU_ADDRESS)

    assert_not order.save
    assert_match(/Insufficient balance/, order.errors.full_messages.to_sentence)
    assert_equal @item.price_for_region("EU"), order.frozen_item_price,
      "the validation must run against the real frozen price, not a nil price it hasn't seen yet"
    assert_equal 50, @user.reload.balance
  end

  test "the model-level balance validation is modifier-inclusive: item price alone fitting isn't enough" do
    grant(120) # covers the US item price (100) plus a little, not the item + a $50-ish modifier

    order = @user.shop_orders.new(
      shop_item: @item, quantity: 1, frozen_address: { "country" => "US", "primary" => true },
      frozen_modifiers_price: 50
    )

    assert_not order.save
    assert_match(/Insufficient balance/, order.errors.full_messages.to_sentence)
    assert_equal 0, ShopOrder.count
    assert_equal 120, @user.reload.balance, "a rejected order must never touch the ledger"
  end

  private

  def grant(amount)
    @user.ledger_entries.create!(amount: amount, reason: "test grant", ledgerable: @user, created_by: "test")
  end

  def with_address(&block) = HCAService.stub(:identity, IDENTITY, &block)

  def build_item(**attributes)
    item = ShopItem.new({ name: "Region Priced Widget", description: "test item",
                          type: "ShopItem::ThirdPartyPhysical", enabled: true }.merge(attributes))
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
