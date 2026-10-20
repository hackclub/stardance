require "test_helper"

class Shop::RegionsControllerTest < ActionDispatch::IntegrationTest
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")
  TURBO_STREAM = { "Accept" => "text/vnd.turbo-stream.html" }

  setup do
    @hardware = ShopCategory.create!(slug: "npl_hw", title: "Hardware", hub_title: "Gadgets")
    @in_cat = build_item("USB Blaster")
    @out_cat = build_item("Hoodie")
    ShopItemCategory.create!(shop_item: @in_cat, shop_category: @hardware)
    ShopItem.invalidate_shop_page_cache!
  end

  test "changing region on a category page only sends back that category's items" do
    patch shop_region_path, params: { region: "EU", category: "npl_hw" }, headers: TURBO_STREAM

    assert_response :success
    assert_includes response.body, "USB Blaster"
    assert_not_includes response.body, "Hoodie"
    assert_includes response.body, "No items match your filters."
  end

  test "changing region without a category sends back every item" do
    patch shop_region_path, params: { region: "EU" }, headers: TURBO_STREAM

    assert_response :success
    assert_includes response.body, "USB Blaster"
    assert_includes response.body, "Hoodie"
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
