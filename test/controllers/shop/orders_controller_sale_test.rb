require "test_helper"

class Shop::OrdersControllerSaleTest < ActionDispatch::IntegrationTest
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze
  US_ADDRESS = { "id" => "addr-us", "country" => "US", "primary" => true }.freeze
  IDENTITY = { "addresses" => [ US_ADDRESS ], "phone_number" => "+15551234567" }.freeze

  setup do
    Flipper.enable(:clearance_sale)
    @user = create_user(slack_id: "U-sale-checkout", display_name: "salecheckout", verified: true)
    @user.update!(has_gotten_free_stickers: true)
    @user.ledger_entries.create!(amount: 1_000, reason: "test grant", ledgerable: @user, created_by: "test")
    @item = ShopItem.new(name: "Clearance Widget", description: "test item", ticket_cost: 100,
                         type: "ShopItem::ThirdPartyPhysical", enabled: true,
                         sale_percentage: 50, sale_step_percentage: 5, sale_starts_at: 1.hour.ago)
    @item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    @item.save!
    sign_in @user
  end

  teardown do
    Flipper.disable(:clearance_sale)
  end

  test "checking out at the discount the buyer saw charges that price" do
    with_address do
      post shop_orders_path, params: { shop_item_id: @item.id, quantity: 1, expected_sale_percentage: 50 }
    end

    assert_equal 50, ShopOrder.sole.frozen_item_price
    assert_equal "Snagged it at 50% off! Bean is thrilled.", flash[:notice]
  end

  test "a discount that shrank since the page loaded asks the buyer to confirm instead of charging more" do
    other = create_user(slack_id: "U-sale-other", display_name: "saleother", verified: true)
    other.update!(has_gotten_free_stickers: true)
    other.ledger_entries.create!(amount: 1_000, reason: "test grant", ledgerable: other, created_by: "test")
    other.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: US_ADDRESS)

    with_address do
      post shop_orders_path, params: { shop_item_id: @item.id, quantity: 1, expected_sale_percentage: 50 }
    end

    assert_redirected_to shop_item_path(@item)
    assert_match(/now 45% off/, flash[:alert])
    assert_equal 0, @user.shop_orders.count
    assert_equal 1_000, @user.reload.balance
  end

  test "a flat sale that ends while the page is open asks to confirm instead of charging full price" do
    @item.update!(sale_step_percentage: 0, sale_starts_at: 2.hours.ago, sale_ends_at: 1.minute.ago)

    with_address do
      post shop_orders_path, params: { shop_item_id: @item.id, quantity: 1, expected_sale_percentage: 50 }
    end

    assert_redirected_to shop_item_path(@item)
    assert_match(/sale just ended/, flash[:alert])
    assert_equal 0, @user.shop_orders.count
  end

  private

  def with_address(&block) = HCAService.stub(:identity!, IDENTITY, &block)
end
