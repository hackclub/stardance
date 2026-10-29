require "test_helper"

# Admins can find an order in the command palette by its carrier tracking
# number, the same way they can by external_ref or id.
class SearchShopOrdersTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @admin = create_user(slack_id: "U_SSO_ADMIN", display_name: "sso_admin")
    @admin.grant_role!(:admin)

    item = ShopItem.new(
      name: "Searchable Patch", description: "A physical item",
      ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true
    )
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!

    @buyer = create_user(slack_id: "U_SSO_BUYER", display_name: "sso_buyer", verified: true)
    @buyer.update!(has_gotten_free_stickers: true)
    @order = @buyer.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: { "country" => "US", "primary" => true })
    @order.update_columns(aasm_state: "fulfilled", external_ref: "ORD-12345", tracking_number: "1Z999AA10123456784")
  end

  test "an admin finds an order by part of its tracking number" do
    sign_in @admin
    get global_search_path(format: :json), params: { q: "1Z999AA1012" }

    assert_response :success
    assert_equal [ @order.id ], response.parsed_body["shop_orders"].map { |result| result["id"] }
  end

  test "non-admins never get order results" do
    sign_in @buyer
    get global_search_path(format: :json), params: { q: "1Z999AA1012" }

    assert_response :success
    assert_empty response.parsed_body["shop_orders"]
  end
end
