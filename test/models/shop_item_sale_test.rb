require "test_helper"

class ShopItemSaleTest < ActiveSupport::TestCase
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze
  US_ADDRESS = { "country" => "US", "primary" => true }.freeze

  setup do
    Flipper.enable(:clearance_sale)
    @buyer = create_user(slack_id: "U-sale-buyer", display_name: "salebuyer", verified: true)
    @buyer.update!(has_gotten_free_stickers: true)
    @buyer.ledger_entries.create!(amount: 10_000, reason: "test grant", ledgerable: @buyer, created_by: "test")
  end

  teardown do
    Flipper.disable(:clearance_sale)
  end

  test "a clearance sale set up ahead of time waits for the flag" do
    Flipper.disable(:clearance_sale)
    item = build_item(sale_name: "Hardware Day", sale_percentage: 50, sale_starts_at: 1.hour.ago, sale_ends_at: 1.hour.from_now)

    assert_not item.on_sale?
    assert_equal 100, item.price_for_region("US")
    assert_equal 100, buy(item).frozen_item_price, "checkout charges full price"

    Flipper.enable(:clearance_sale)
    assert item.on_sale?
    assert_equal 50, item.price_for_region("US")
  end

  test "the flag has to be on for everyone, not just one person" do
    Flipper.disable(:clearance_sale)
    Flipper.enable_actor(:clearance_sale, @buyer)
    item = build_item(sale_name: "Hardware Day", sale_percentage: 50)

    assert_not item.on_sale?
  end

  test "an ordinary always-on discount doesn't wait for the flag" do
    Flipper.disable(:clearance_sale)
    item = build_item(sale_percentage: 20)

    assert item.on_sale?
    assert_not item.clearance_sale?
  end

  test "a sale without a window is a flat, always-on discount" do
    item = build_item(sale_percentage: 20)

    assert item.sale_active?
    assert_equal 20, item.current_sale_percentage
    assert_equal 80, item.price_for_region("US")
  end

  test "a windowed sale only applies inside its window" do
    item = build_item(sale_percentage: 50, sale_starts_at: 1.hour.from_now, sale_ends_at: 2.hours.from_now)

    assert item.sale_upcoming?
    assert_not item.on_sale?
    assert_equal 100, item.price_for_region("US")

    travel 90.minutes do
      assert item.on_sale?
      assert_equal 50, item.price_for_region("US")
    end

    travel 3.hours do
      assert_not item.on_sale?
      assert_equal 100, item.price_for_region("US")
    end
  end

  test "each unit sold during the sale knocks the step off, down to the minimum" do
    item = build_item(sale_percentage: 50, sale_step_percentage: 5, sale_min_percentage: 40,
                      sale_starts_at: 1.hour.ago, sale_ends_at: 1.hour.from_now)

    assert_equal 50, item.current_sale_percentage
    assert_equal 45, item.next_sale_percentage

    buy(item, quantity: 1)
    assert_equal 45, item.current_sale_percentage
    assert_equal 55, item.price_for_region("US")

    buy(item, quantity: 3)
    assert_equal 40, item.current_sale_percentage, "never drops below the minimum"
    assert_nil item.next_sale_percentage
  end

  test "orders from before the sale and rejected orders don't shrink the discount" do
    item = build_item(sale_percentage: 50, sale_step_percentage: 5, sale_starts_at: 1.hour.ago)

    buy(item).update_columns(created_at: 2.hours.ago)
    buy(item).update_columns(aasm_state: "rejected")

    assert_equal 0, item.sale_units_sold
    assert_equal 50, item.current_sale_percentage
  end

  test "an order freezes the discount at the moment it's placed" do
    item = build_item(sale_percentage: 50, sale_step_percentage: 10, sale_starts_at: 1.hour.ago)

    first = buy(item)
    second = buy(item)

    assert_equal 50, first.frozen_item_price
    assert_equal 60, second.frozen_item_price
  end

  test "preload_sale_units_sold matches the per-item count" do
    decaying = build_item(sale_percentage: 50, sale_step_percentage: 5, sale_starts_at: 1.hour.ago)
    flat = build_item(sale_percentage: 30)
    buy(decaying, quantity: 2)

    items = ShopItem.where(id: [ decaying.id, flat.id ]).to_a
    ShopItem.preload_sale_units_sold(items)
    preloaded = items.find { |i| i.id == decaying.id }

    assert_equal 2, preloaded.sale_units_sold
    assert_equal 40, preloaded.current_sale_percentage
    assert_equal 30, items.find { |i| i.id == flat.id }.current_sale_percentage
  end

  test "sale settings are validated" do
    item = build_item
    item.assign_attributes(sale_percentage: 50, sale_step_percentage: 5)
    assert_not item.valid?
    assert item.errors[:sale_starts_at].any?

    item.assign_attributes(sale_starts_at: 1.hour.from_now, sale_ends_at: 1.hour.ago)
    assert_not item.valid?
    assert item.errors[:sale_ends_at].any?

    item.assign_attributes(sale_ends_at: 2.hours.from_now, sale_min_percentage: 60)
    assert_not item.valid?
    assert item.errors[:sale_min_percentage].any?
  end

  test "fulfiller lookup skips accounts that no longer exist" do
    fulfiller = create_user(slack_id: "U-fulfiller", display_name: "fulfiller", verified: true)
    item = build_item(default_assigned_user_id: fulfiller.id, default_assigned_user_id_uk: fulfiller.id + 10_000)

    assert_equal fulfiller.id, item.default_assignee_for_region("UK"), "falls back to the general fulfiller"

    item.update!(default_assigned_user_id: nil)
    assert_nil item.default_assignee_for_region("UK"), "no fulfiller beats a missing one"
  end

  private

  def buy(item, quantity: 1)
    @buyer.shop_orders.create!(shop_item: item, quantity: quantity, frozen_address: US_ADDRESS)
  end

  def build_item(**attributes)
    item = ShopItem.new({ name: "Clearance Widget", description: "test item", ticket_cost: 100,
                          type: "ShopItem::ThirdPartyPhysical", enabled: true }.merge(attributes))
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
