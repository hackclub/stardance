class Api::V1::Users::Me::WishlistController < Api::BaseController
  include ApiAuthenticatable

  def index
    @wishlists = current_api_user.shop_wishlists
                                 .includes(shop_item: [ :shop_categories, image_attachment: :blob ])
                                 .order(created_at: :desc)
    @user_region = current_api_user.shop_region || "XX"
  end

  def create
    shop_item = ShopItem.find(params[:id])
    current_api_user.shop_wishlists.find_or_create_by!(shop_item: shop_item)
    render json: { wishlisted: true }
  end

  def destroy
    current_api_user.shop_wishlists.where(shop_item_id: params[:id]).destroy_all
    render json: { wishlisted: false }
  end
end
