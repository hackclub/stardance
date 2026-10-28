require "test_helper"

class Shop::ItemsControllerTest < ActionDispatch::IntegrationTest
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    Flipper.enable(:shop_open)
    @hardware = ShopCategory.create!(slug: "npl_hw", title: "Hardware", hub_title: "Gadgets")
    @in_cat = build_item("USB Blaster")
    @out_cat = build_item("Hoodie")
    ShopItemCategory.create!(shop_item: @in_cat, shop_category: @hardware)
    ShopItem.invalidate_shop_page_cache!
  end

  teardown do
    Flipper.disable(:shop_open)
    Flipper.disable(:clearance_sale)
  end

  test "category page for a real slug returns 200 with filtered items" do
    get shop_category_path("npl_hw")

    assert_response :success
    assert_select "h1.shop-category__title", "Hardware"
    assert_includes response.body, "USB Blaster"
    assert_not_includes response.body, "Hoodie"
  end

  test "category page for all returns 200 with every item" do
    get shop_category_path("all")

    assert_response :success
    assert_select "h1.shop-category__title", "All"
    assert_includes response.body, "USB Blaster"
    assert_includes response.body, "Hoodie"
  end

  test "sale page is hidden until the clearance flag is on" do
    get shop_category_path("sale")

    assert_response :not_found
  end

  test "sale page lists only items currently on sale" do
    Flipper.enable(:clearance_sale)
    @out_cat.update!(sale_percentage: 30)
    ShopItem.invalidate_shop_page_cache!

    get shop_category_path("sale")

    assert_response :success
    assert_select "h1.shop-category__title", "Clearance"
    assert_includes response.body, "Hoodie"
    assert_not_includes response.body, "USB Blaster"
  end

  test "item cards check mission locks without a query per card" do
    3.times { |i| build_item("Sticker #{i}") }
    mission = Mission.create!(slug: "shop-gate", name: "Shop Gate", description: "Unlocks the blaster.")
    Mission::ShopUnlock.create!(mission: mission, shop_item: @in_cat)
    ShopItem.invalidate_shop_page_cache!

    assert_queries_match(/FROM "mission_shop_unlocks" WHERE "mission_shop_unlocks"\."shop_item_id" = \$1/, count: 0) do
      get shop_category_path("all")
    end

    assert_response :success
    assert_select ".shop-item-card--mission-locked", 1
    assert_select ".shop-item-card--mission-locked", text: /USB Blaster/
  end

  private

  def build_item(name)
    item = ShopItem.new(
      name: name,
      description: "test item",
      ticket_cost: 10,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
