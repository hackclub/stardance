require "test_helper"

class Api::V1::ShopOrdersControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze
  UPS = "1Z999AA10123456784".freeze

  setup do
    @packer = create_user(slack_id: "U_API_SO_PACKER", display_name: "api_packer")
    @packer.grant_role!(:fulfillment_person)
    @packer.regenerate_api_key

    item = ShopItem.new(
      name: "API Printer", description: "A physical item",
      ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!

    @buyer = create_user(slack_id: "U_API_SO_BUYER", display_name: "api_buyer", verified: true)
    @buyer.update!(has_gotten_free_stickers: true)
    @order = @buyer.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: { "country" => "AU", "primary" => true, "line_one" => "1 Secret St" })
    @order.update_columns(aasm_state: "fulfilled", fulfilled_at: 1.day.ago, external_ref: "Bambu AU AU787303367675330561", region: "AU")
  end

  test "requires an api key" do
    get api_v1_shop_order_path(@order)
    assert_response :unauthorized

    patch api_v1_shop_order_path(@order), params: { tracking_number: UPS }, headers: { "Authorization" => "Bearer nope" }
    assert_response :unauthorized
    assert_nil @order.reload.tracking_number
  end

  test "is forbidden for users without fulfillment access" do
    assert_forbidden_for create_user(slack_id: "U_API_SO_PLAIN", display_name: "api_plain")
  end

  test "is forbidden for the fraud dept" do
    reviewer = create_user(slack_id: "U_API_SO_FRAUD", display_name: "api_fraud")
    reviewer.grant_role!(:fraud_dept)

    assert_forbidden_for reviewer
  end

  test "shows an order without address or buyer details" do
    get api_v1_shop_order_path(@order), headers: auth_headers

    assert_response :success
    assert_equal(
      {
        "id" => @order.id, "aasm_state" => "fulfilled", "item_name" => "API Printer",
        "external_ref" => "Bambu AU AU787303367675330561", "tracking_number" => nil,
        "fulfillment_cost" => nil, "fulfilled_at" => @order.fulfilled_at.as_json, "region" => "AU"
      },
      response.parsed_body
    )
  end

  test "search finds an order by a store order number inside external_ref" do
    get api_v1_shop_orders_path(query: "au787303367675330561"), headers: auth_headers

    assert_response :success
    assert_equal [ @order.id ], response.parsed_body["shop_orders"].map { |order| order["id"] }
  end

  test "search finds an order by tracking number and requires a query" do
    @order.update_columns(tracking_number: UPS)

    get api_v1_shop_orders_path(query: UPS), headers: auth_headers
    assert_equal [ @order.id ], response.parsed_body["shop_orders"].map { |order| order["id"] }

    get api_v1_shop_orders_path(query: "AULA-0000"), headers: auth_headers
    assert_empty response.parsed_body["shop_orders"]

    get api_v1_shop_orders_path, headers: auth_headers
    assert_response :bad_request
  end

  test "setting tracking DMs the buyer and is audit logged under the key's owner" do
    assert_difference -> { Notifications::ShopOrders::TrackingUpdated.where(record: @order).count }, 1 do
      patch api_v1_shop_order_path(@order), params: { tracking_number: " #{UPS} " }, headers: auth_headers, as: :json
    end

    assert_response :success
    assert_equal UPS, response.parsed_body["tracking_number"]
    assert_equal UPS, @order.reload.tracking_number

    audit = @order.versions.find_by!(event: "tracking_updated")
    assert_equal @packer.id.to_s, audit.whodunnit
    assert_equal [ nil, UPS ], audit.object_changes["tracking_number"]
    assert_equal @packer.id.to_s, @order.versions.where(event: "update").last.whodunnit
  end

  test "updating requires tracking_number" do
    patch api_v1_shop_order_path(@order), params: {}, headers: auth_headers, as: :json

    assert_response :bad_request
  end

  test "address returns the decrypted address and is audit logged under the key's owner" do
    assert_difference -> { @order.versions.where(event: "address_access").count }, 1 do
      get address_api_v1_shop_order_path(@order), headers: auth_headers
    end

    assert_response :success
    assert_equal({ "id" => @order.id, "address" => @order.frozen_address }, response.parsed_body)
    assert_equal @packer.id.to_s, @order.versions.find_by!(event: "address_access").whodunnit

    revealed = PaperTrail::Version.find_by!(item_type: "User", item_id: @buyer.id, event: "address_revealed")
    assert_equal @packer.id.to_s, revealed.whodunnit
  end

  test "address respects the packer's assigned regions" do
    @packer.update!(regions: [ "US" ])

    get address_api_v1_shop_order_path(@order), headers: auth_headers

    assert_response :forbidden
    assert_not @order.versions.exists?(event: "address_access")
  end

  test "address is hidden for digital items" do
    @order.shop_item.update_columns(type: ShopOrder::DIGITAL_FULFILLMENT_TYPES.first)

    get address_api_v1_shop_order_path(@order), headers: auth_headers

    assert_response :forbidden
  end

  test "fulfill marks an awaiting order fulfilled with cost, reference and tracking" do
    await_fulfillment!

    assert_difference -> { Notifications::ShopOrders::StatusChanged.where(record: @order).count }, 1 do
      post fulfill_api_v1_shop_order_path(@order),
           params: { external_ref: "Amazon 113-1234567", fulfillment_cost: "24.99", tracking_number: " #{UPS} " },
           headers: auth_headers, as: :json
    end

    assert_response :success
    assert_equal "fulfilled", response.parsed_body["aasm_state"]

    @order.reload
    assert @order.fulfilled?
    assert_equal "Amazon 113-1234567", @order.external_ref
    assert_equal BigDecimal("24.99"), @order.fulfillment_cost
    assert_equal UPS, @order.tracking_number
    assert_equal @packer.display_name, @order.fulfilled_by

    audit = @order.versions.where(event: "update").last
    assert_equal @packer.id.to_s, audit.whodunnit
  end

  test "fulfill works without any details, like the admin page" do
    await_fulfillment!

    post fulfill_api_v1_shop_order_path(@order), params: {}, headers: auth_headers, as: :json

    assert_response :success
    assert @order.reload.fulfilled?
  end

  test "fulfill rejects orders that are not awaiting fulfillment" do
    post fulfill_api_v1_shop_order_path(@order), params: { external_ref: "X" }, headers: auth_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "Bambu AU AU787303367675330561", @order.reload.external_ref
  end

  test "fulfill rejects a negative or non-numeric cost" do
    await_fulfillment!

    [ "-1", "lots" ].each do |cost|
      post fulfill_api_v1_shop_order_path(@order), params: { fulfillment_cost: cost }, headers: auth_headers, as: :json

      assert_response :bad_request
    end
    assert @order.reload.awaiting_periodical_fulfillment?
  end

  test "an unknown order is not found" do
    get api_v1_shop_order_path(0), headers: auth_headers

    assert_response :not_found
  end

  private

  def assert_forbidden_for(user)
    user.regenerate_api_key
    headers = { "Authorization" => "Bearer #{user.api_key}" }

    get api_v1_shop_orders_path(query: "AU787"), headers: headers
    assert_response :forbidden

    patch api_v1_shop_order_path(@order), params: { tracking_number: UPS }, headers: headers
    assert_response :forbidden
    assert_nil @order.reload.tracking_number

    get address_api_v1_shop_order_path(@order), headers: headers
    assert_response :forbidden

    await_fulfillment!
    post fulfill_api_v1_shop_order_path(@order), params: { external_ref: "X" }, headers: headers
    assert_response :forbidden
    assert @order.reload.awaiting_periodical_fulfillment?
  end

  def await_fulfillment!
    @order.update_columns(aasm_state: "awaiting_periodical_fulfillment", fulfilled_at: nil, external_ref: nil)
  end

  def auth_headers
    { "Authorization" => "Bearer #{@packer.api_key}" }
  end
end
