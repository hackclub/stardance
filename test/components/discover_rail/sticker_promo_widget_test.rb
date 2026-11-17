require "test_helper"

class DiscoverRail::StickerPromoWidgetTest < ViewComponent::TestCase
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    travel_to StickerPromo.window_start + 1.day
    @user = create_user(slack_id: "U_STICKER_PROMO", display_name: "sticker_promo")
    @user.update!(onboarded_at: 1.week.ago, has_gotten_free_stickers: true)
    @user.projects.create!(title: "Shipped", shipped_at: Time.current)
    @sticker = build_sticker
  end

  teardown { travel_back }

  test "offers the claim link to someone who shipped this week" do
    render_widget

    assert_selector ".sticker-promo-widget__claim[href='/shop/items/#{@sticker.id}']", text: "Claim your sticker"
  end

  test "goes away once the sticker is ordered" do
    order_sticker

    render_widget

    assert_no_selector ".sticker-promo-widget"
  end

  test "comes back if the order was rejected" do
    order_sticker.update_columns(aasm_state: "rejected")

    render_widget

    assert_selector ".sticker-promo-widget__claim"
  end

  private

  def render_widget
    StickerPromo.stub(:shop_item_id, @sticker.id) do
      render_inline(DiscoverRail::StickerPromoWidget.new(user: @user))
    end
  end

  def order_sticker
    @user.shop_orders.create!(shop_item: @sticker, quantity: 1, frozen_address: { "country" => "US" }, frozen_item_price: 0)
  end

  def build_sticker
    item = ShopItem.new(name: "Stardance Sticker", description: "sticker", ticket_cost: 0, usd_cost: 1,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true, unlisted: true)
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
