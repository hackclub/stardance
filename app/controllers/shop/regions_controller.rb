class Shop::RegionsController < Shop::BaseController
  def update
    region = params[:region]&.upcase
    unless Shop::Regionalizable::REGION_CODES.include?(region)
      return head :unprocessable_entity
    end

    if current_user
      if current_user.shop_region != region
        current_user.update_column(:shop_region, region)
        current_user.shop_region = region
      end
    else
      session[:shop_region] = region
    end

    @user_region = region
    load_shop_items
    @wishlisted_item_ids = current_user&.shop_wishlists&.pluck(:shop_item_id) || []
    prepare_visible_shop_items

    respond_to do |format|
      format.turbo_stream
      format.html { head :ok }
    end
  end
end
