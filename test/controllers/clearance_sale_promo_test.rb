require "test_helper"

# The site-wide clearance promotion: discover-rail card, "sale" nav tag and a
# one-time pop-up, all hidden until the clearance_sale flag is on.
class ClearanceSalePromoTest < ActionDispatch::IntegrationTest
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    Flipper.enable(:shop_open)
    @user = users(:one)
    @user.update!(verification_status: :verified, ysws_eligible: true)
    item = ShopItem.new(name: "Promo Widget", description: "test item", ticket_cost: 100,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true,
                        sale_name: "Hardware Day", sale_percentage: 50,
                        sale_starts_at: 1.hour.ago, sale_ends_at: 5.hours.from_now)
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    ShopItem.invalidate_shop_page_cache!
    sign_in @user
  end

  teardown do
    Flipper.disable(:shop_open)
    Flipper.disable(:clearance_sale)
  end

  test "nothing is advertised while the flag is off" do
    get home_path

    assert_select ".clearance-popup", 0
    assert_select ".clearance-sale-widget", 0
    assert_select ".sidebar__nav-tag", 0
  end

  test "with the flag on, home shows the pop-up, rail card and nav tag" do
    Flipper.enable(:clearance_sale)

    get home_path

    assert_select ".clearance-popup .clearance-popup__title", "Hardware Day"
    assert_select ".clearance-sale-widget[href=?]", "/shop/category/sale", text: /up to\s+50% off/
    assert_select ".sidebar__nav-tag", "sale"
  end

  test "the pop-up stays dismissed for that sale" do
    Flipper.enable(:clearance_sale)
    get home_path
    cookie = css_select(".clearance-popup").first["data-dismissable-cookie-value"]

    cookies[cookie] = "1"
    get home_path

    assert_select ".clearance-popup", 0
    assert_select ".clearance-sale-widget", 1
  end
end
