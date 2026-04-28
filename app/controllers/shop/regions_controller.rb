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

  private

  def load_shop_items
    excluded_free_stickers = current_user && has_ordered_free_stickers?
    shop_page_data = ShopItem.cached_shop_page_data
    @shop_items = shop_page_data[:buyable_standalone]
    @shop_items = @shop_items.reject { |item| item.type == "ShopItem::FreeStickers" } if excluded_free_stickers
    @featured_item = featured_free_stickers_item unless excluded_free_stickers
    @recently_added_items = shop_page_data[:recently_added]
    @user_balance = current_user&.cached_balance || 0
  end

  def has_ordered_free_stickers?
    current_user.has_gotten_free_stickers? ||
      current_user.shop_orders.joins(:shop_item).where(shop_items: { type: "ShopItem::FreeStickers" }).exists?
  end

  def featured_free_stickers_item
    item = ShopItem.find_by(id: 1, type: "ShopItem::FreeStickers", enabled: true)
    item if item&.enabled_in_region?(@user_region)
  end
end
