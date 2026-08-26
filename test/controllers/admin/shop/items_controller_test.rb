require "test_helper"

# The HCB source-org picker lets an admin route a grant item's card grant to a
# specific HCB org. These cover the admin form + params plumbing behind it.
class Admin::Shop::ItemsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @admin = create_user(slack_id: "U_ITEMS_ADMIN", display_name: "items_admin")
    @admin.grant_role!(:admin)

    @grant_item = ShopItem::HCBGrant.new(
      name: "Grant Item", description: "A grant", ticket_cost: 0, usd_cost: 25, enabled: true
    )
    @grant_item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    @grant_item.save!
  end

  test "updating a grant item persists the chosen hcb org" do
    sign_in @admin
    patch admin_shop_item_path(@grant_item), params: { shop_item: { hcb_org_slug: "stardance-hardware" } }

    assert_redirected_to admin_shop_item_path(@grant_item)
    assert_equal "stardance-hardware", @grant_item.reload.hcb_org_slug
  end

  test "the org picker is shown for grant items" do
    sign_in @admin
    get edit_admin_shop_item_path(@grant_item)

    assert_response :success
    assert_select "input[type=radio][name='shop_item[hcb_org_slug]'][value=stardance]"
    assert_select "input[type=radio][name='shop_item[hcb_org_slug]'][value='stardance-hardware']"
  end

  test "the org picker is hidden for non-grant items" do
    non_grant = ShopItem::ThirdPartyPhysical.new(
      name: "Patch", description: "physical", ticket_cost: 0, usd_cost: 5, enabled: true
    )
    non_grant.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    non_grant.save!

    sign_in @admin
    get edit_admin_shop_item_path(non_grant)

    assert_response :success
    assert_select "input[name='shop_item[hcb_org_slug]']", count: 0
  end
end
