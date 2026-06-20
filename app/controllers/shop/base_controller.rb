class Shop::BaseController < ApplicationController
  private

  def user_region
    if current_user
      return current_user.shop_region if current_user.shop_region.present?
      return current_user.regions.first if current_user.has_regions?

      primary_address = (@user_addresses ||= current_user.addresses).find { |a| a["primary"] } || @user_addresses.first
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
    shop_page_data = ShopItem.cached_shop_page_data
    @shop_items = shop_page_data[:buyable_standalone]
    @shop_items = @shop_items.reject { |item| item.type.in?(%w[ShopItem::FreeStickers ShopItem::TutorialNothing]) }
    @recently_added_items = shop_page_data[:recently_added]
    @user_balance = current_user&.cached_balance || 0

    preload_shop_item_images(@shop_items + Array(@recently_added_items))
  end

  def prepare_visible_shop_items(items = @shop_items)
    @visible_shop_items = Array(items).select { |item| item.image.attached? && item.enabled_in_region?(@user_region) }
  end

  def preload_shop_item_images(items)
    items = items.compact.uniq
    return if items.empty?

    ActiveRecord::Associations::Preloader.new(
      records: items,
      associations: { image_attachment: [ :blob, :record ] }
    ).call
  end

  def tutorial_item?(shop_item)
    shop_item.is_a?(ShopItem::FreeStickers) || shop_item.is_a?(ShopItem::TutorialNothing)
  end

  def derive_shop_mode
    return :preview if current_user.nil? || current_user.guest?
    return :preview unless current_user.projects.exists?
    return :preview unless current_user.hackatime_identity.present?
    return :preview unless current_user.identity_submitted?
    return :preview unless Post.where(user: current_user, postable_type: "Post::Devlog").exists?
    return :tutorial if current_user.shop_tutorial_needed?

    :normal
  end

  def load_tutorial_items
    {
      stickers: ShopItem::FreeStickers.where(enabled: true).first,
      nothing:  ShopItem::TutorialNothing.where(enabled: true).first
    }
  end

  def load_redeemable_submission(shop_item)
    return nil unless current_user
    submission_id = params[:mission_submission_id]
    return nil if submission_id.blank?

    submission = Mission::Submission
      .includes(mission: :prizes, ship_event: { post: :user })
      .find_by(id: submission_id)
    return nil unless submission
    return nil unless submission.approved?
    return nil unless submission.shop_order_id.nil?
    return nil unless submission.ship_event&.post&.user_id == current_user.id
    return nil unless submission.mission.prizes.exists?(shop_item_id: shop_item.id)

    submission
  end
end
