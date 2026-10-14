require "test_helper"

class Shop::ProcessWarehouseOrdersJobTest < ActiveJob::TestCase
  include UserFactory

  THESEUS_RESPONSE = { "warehouse_order" => { "id" => "who_test" } }.freeze

  setup do
    @user = create_user(slack_id: "u-warehouse", display_name: "warehouse-user")
    @user.update!(has_gotten_free_stickers: true)
    @item = ShopItem::WarehouseItem.new(
      name: "Test Warehouse Item",
      description: "A warehouse item",
      ticket_cost: 0,
      enabled: true,
      agh_contents: [ { "sku" => "Sti/Test/1st", "quantity" => 1 } ]
    )
    @item.image.attach(
      io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
      filename: "px.png", content_type: "image/png"
    )
    @item.save!
  end

  test "sends the package to Theseus when the selected address has a phone number" do
    order = create_warehouse_order(frozen_address: { "country" => "US", "phone_number" => "+15555550123" })

    TheseusService.stub(:create_warehouse_order, THESEUS_RESPONSE) do
      Shop::ProcessWarehouseOrdersJob.perform_now
    end

    assert order.reload.fulfilled?
    assert_equal "who_test", order.warehouse_package.theseus_package_id
  end

  test "skips the package and leaves orders pending when the selected address has no phone number" do
    order = create_warehouse_order(frozen_address: { "country" => "US" })

    TheseusService.stub(:create_warehouse_order, ->(*) { flunk "must not submit to Theseus without a phone number" }) do
      Shop::ProcessWarehouseOrdersJob.perform_now
    end

    assert order.reload.awaiting_periodical_fulfillment?
    assert_nil order.warehouse_package_id
    assert_equal 0, ShopWarehousePackage.where(user: @user).count
  end

  private

  def create_warehouse_order(frozen_address:)
    order = @user.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: frozen_address)
    order.update!(aasm_state: "awaiting_periodical_fulfillment")
    order
  end
end
