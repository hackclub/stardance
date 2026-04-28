class Shop::BaseController < ApplicationController
  private

  def require_login
    redirect_to root_path, alert: "Please log in first" and return unless current_user
  end

  def user_region
    if current_user
      return current_user.shop_region if current_user.shop_region.present?
      return current_user.regions.first if current_user.has_regions?

      primary_address = current_user.addresses.find { |a| a["primary"] } || current_user.addresses.first
      country = primary_address&.dig("country")
      region_from_address = Shop::Regionalizable.country_to_region(country)
      return region_from_address if region_from_address != "XX" || country.present?
    else
      return session[:shop_region] if session[:shop_region].present? && Shop::Regionalizable::REGION_CODES.include?(session[:shop_region])
    end

    cached = cookies[:geoip_region]
    return cached if cached.present? && cached != "XX" && Shop::Regionalizable::REGION_CODES.include?(cached)

    tz_region = Shop::Regionalizable.timezone_to_region(cookies[:timezone])
    return tz_region if tz_region.present? && tz_region != "XX"

    "US"
  end

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
