require "test_helper"

class OgImageShopOrderFlexTest < ActiveSupport::TestCase
  include UserFactory

  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @user = create_user(slack_id: "u-flex", display_name: "flexer")
    @item = build_item(name: "Hardware Build Fund")
    @order = ShopOrder.new(shop_item: @item, user: @user, quantity: 1)
  end

  test "renders a 1200x1200 png" do
    png = OgImage::ShopOrderFlex.new(@order).to_png

    assert png.start_with?("\x89PNG".b), "output must be a PNG"
    image = Vips::Image.new_from_buffer(png, "")
    assert_equal 1200, image.width
    assert_equal 1200, image.height
  end

  test "survives item names with pango markup characters" do
    @item.update!(name: "Solder & <Iron> Kit")

    assert_nothing_raised do
      OgImage::ShopOrderFlex.new(@order).to_png
    end
  end

  private

  def build_item(name:)
    item = ShopItem.new(
      name: name,
      description: "Flex card test item",
      ticket_cost: 0,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
