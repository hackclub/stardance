class Shop::RegionsController < Shop::BaseController
  def update
    region = params[:region]&.upcase
    unless Shop::Regionalizable::REGION_CODES.include?(region)
      return head :unprocessable_entity
    end

    if current_user
      current_user.update!(shop_region: region)
    else
      session[:shop_region] = region
    end

    @user_region = region
    load_shop_items

    respond_to do |format|
      format.turbo_stream
      format.html { head :ok }
    end
  end

end
