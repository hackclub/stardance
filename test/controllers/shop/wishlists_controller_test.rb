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

  test "removing without turbo redirects back to the shop" do
    delete shop_wishlist_path(@item.id)

    assert_redirected_to shop_path
  end
end
