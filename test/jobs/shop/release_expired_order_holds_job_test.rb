require "test_helper"

class Shop::ReleaseExpiredOrderHoldsJobTest < ActiveJob::TestCase
  setup do
    user = User.create!(
      slack_id: "U_EXPIRED_HOLD_#{SecureRandom.hex(6)}",
      email: "expired-hold-#{SecureRandom.hex(4)}@example.com",
      display_name: "Expired Hold User"
    )
    item = ShopItem.create!(
      name: "Held Item #{SecureRandom.hex(4)}",
      ticket_cost: 0,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    @order = user.shop_orders.new(
      shop_item: item,
      quantity: 1,
      frozen_item_price: 0,
      frozen_address: { "country" => "US" },
      aasm_state: "on_hold"
    )
    @order.save!(validate: false)
  end

  test "releases an order after seven days on hold and audits the transition" do
    now = Time.zone.parse("2026-09-09 12:00:00")
    @order.update_columns(on_hold_at: now - 7.days, updated_at: now - 7.days)

    Shop::ReleaseExpiredOrderHoldsJob.perform_now(now)

    assert_predicate @order.reload, :pending?
    version = @order.versions.order(:created_at).last
    assert_equal "automatic_hold_release", version.event
    assert_equal "Shop::ReleaseExpiredOrderHoldsJob", version.whodunnit
  end

  test "does not release an order before seven days" do
    now = Time.zone.parse("2026-09-09 12:00:00")
    @order.update_columns(on_hold_at: now - 7.days + 1.second, updated_at: now - 7.days + 1.second)

    Shop::ReleaseExpiredOrderHoldsJob.perform_now(now)

    assert_predicate @order.reload, :on_hold?
  end

  test "uses updated_at for legacy holds without an on-hold timestamp" do
    now = Time.zone.parse("2026-09-09 12:00:00")
    @order.update_columns(on_hold_at: nil, updated_at: now - 8.days)

    Shop::ReleaseExpiredOrderHoldsJob.perform_now(now)

    assert_predicate @order.reload, :pending?
  end
end
