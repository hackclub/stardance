require "test_helper"

# Region/country filters on the fulfilment queue. Region already existed but
# was hidden from fulfillment staff and its options didn't match the model's
# 7 regions (UK was folded into EU). Country is new: it reads a plain,
# indexed `country` column (backfilled from the encrypted shipping address)
# rather than decrypting every row.
class Admin::Shop::OrdersControllerRegionCountryFilterTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @admin = create_user(slack_id: "U_RC_ADMIN", display_name: "rc_admin")
    @admin.grant_role!(:admin)

    @item = ShopItem.new(
      name: "Filter Test Item", description: "test item",
      ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true
    )
    @item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    @item.save!

    @de_order = order_for("de-buyer", country: "DE")
    @us_order = order_for("us-buyer", country: "US")
  end

  test "the region select offers all 7 regions, with UK separate from EU" do
    sign_in @admin
    get admin_shop_orders_path(view: "fulfillment")

    assert_response :success
    assert_select "select#region option[value=EU]", text: "EU"
    assert_select "select#region option[value=UK]", text: "United Kingdom"
  end

  test "the country select is present and offers real countries" do
    sign_in @admin
    get admin_shop_orders_path(view: "fulfillment")

    assert_select "select#country option[value=DE]", text: "Germany"
  end

  test "a plain fulfillment person (no region restriction) also sees the region and country filters" do
    fulfiller = create_user(slack_id: "U_RC_FULFILLER", display_name: "rc_fulfiller")
    fulfiller.grant_role!(:fulfillment_person)

    sign_in fulfiller
    get admin_shop_orders_path(view: "fulfillment")

    assert_response :success
    assert_select "select#region"
    assert_select "select#country"
  end

  test "filtering by region narrows the queue" do
    sign_in @admin
    get admin_shop_orders_path(view: "fulfillment", region: "EU")

    assert_includes rendered_order_ids, @de_order.id
    assert_not_includes rendered_order_ids, @us_order.id
  end

  test "filtering by country narrows the queue to that exact country" do
    sign_in @admin
    get admin_shop_orders_path(view: "fulfillment", country: "DE")

    assert_includes rendered_order_ids, @de_order.id
    assert_not_includes rendered_order_ids, @us_order.id
  end

  test "a region-restricted fulfillment person cannot use the country filter to see outside their region" do
    fulfiller = create_user(slack_id: "U_RC_RESTRICTED", display_name: "rc_restricted")
    fulfiller.grant_role!(:fulfillment_person)
    fulfiller.update!(regions: [ "US" ])

    sign_in fulfiller
    get admin_shop_orders_path(view: "fulfillment", country: "DE")

    assert_not_includes rendered_order_ids, @de_order.id,
      "a country param outside the assigned regions must not widen visibility"
  end

  test "a region-restricted fulfillment person can still narrow within their own assigned region" do
    fulfiller = create_user(slack_id: "U_RC_NARROW", display_name: "rc_narrow")
    fulfiller.grant_role!(:fulfillment_person)
    fulfiller.update!(regions: %w[US EU])

    sign_in fulfiller
    get admin_shop_orders_path(view: "fulfillment", region: "EU")

    assert_includes rendered_order_ids, @de_order.id
    assert_not_includes rendered_order_ids, @us_order.id
  end

  private

  def order_for(name, country:)
    user = create_user(slack_id: "U_RC_#{name}", display_name: "rc_#{name.tr('-', '_')}", verified: true)
    user.update!(has_gotten_free_stickers: true)
    address = { "country" => country, "primary" => true }
    order = user.shop_orders.create!(shop_item: @item, quantity: 1, frozen_address: address)
    order.update_columns(aasm_state: "awaiting_periodical_fulfillment")
    order
  end

  # Ids in the order the table rendered them.
  def rendered_order_ids
    css_select("tbody tr td:first-child").map { |cell| cell.text[/#(\d+)/, 1].to_i }
  end
end
