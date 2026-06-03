# frozen_string_literal: true

class Shop::WishlistsController < Shop::BaseController
  def create
    authorize :shop
    current_user.shop_wishlists.find_or_create_by!(shop_item_id: params[:id])
    render json: { wishlisted: true }
  end

  def destroy
    authorize :shop
    current_user.shop_wishlists.where(shop_item_id: params[:id]).destroy_all
    render json: { wishlisted: false }
  end
end
