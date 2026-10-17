require "test_helper"

class Shop::WishlistsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @item = shop_items(:one)
    sign_in(@user)
    @user.shop_wishlists.create!(shop_item: @item)
  end

  test "removing from the sidebar via a turbo form submission returns a turbo stream, not json" do
    delete shop_wishlist_path(@item.id), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_not @user.shop_wishlists.exists?(shop_item: @item)
  end

  test "the refreshed wishlist prices items for the viewer's region" do
    @user.update_column(:shop_region, "EU")
    @user.shop_wishlists.destroy_all
    item = ShopItem.new(name: "Region Priced", description: "test item", ticket_cost: 10_000_000,
                        usd_offset_eu: 100, type: "ShopItem::ThirdPartyPhysical", enabled: true)
    item.image.attach(io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
                      filename: "px.png", content_type: "image/png")
    item.save!
    assert_not_equal item.price_for_region("US"), item.price_for_region("EU")

    post shop_wishlist_path(item.id), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    needed = [ item.price_for_region("EU") - (@user.reload.cached_balance || 0), 0 ].max
    assert_includes response.body, "#{ActiveSupport::NumberHelper.number_to_delimited(needed)} more needed"
  end

  test "removing without turbo redirects back to the shop" do
    delete shop_wishlist_path(@item.id)

    assert_redirected_to shop_path
  end
end
