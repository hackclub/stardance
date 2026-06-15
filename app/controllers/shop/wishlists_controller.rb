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

    respond_to do |format|
      format.json { render json: { wishlisted: false } }
      format.turbo_stream { render turbo_stream: turbo_stream.remove("shop_wishlist_item_#{params[:id]}") }
    end
  end
end
