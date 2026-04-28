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
end
