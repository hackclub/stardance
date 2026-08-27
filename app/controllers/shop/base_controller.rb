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
      associations: { image_attachment: :blob }
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

  # The approval that unlocks a free redemption for this item: an after-ship
  # submission, an after-design funding kit, or a completed Sticky Streak day.
  # Returns the gate record or nil.
  def load_redeemable_gate(shop_item)
    load_redeemable_submission(shop_item) ||
      load_redeemable_funding_request(shop_item) ||
      load_redeemable_sticky_streak_day(shop_item)
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
    return nil unless submission.ship_event&.post&.user_id == current_user.id
    # Each after-ship prize is claimable once per submission.
    return nil unless submission.redeemable_prize_for(shop_item)

    submission
  end

  def load_redeemable_funding_request(shop_item)
    return nil unless current_user
    funding_request_id = params[:funding_request_id]
    return nil if funding_request_id.blank?

    funding_request = Certification::FundingRequest
      .includes(project: [ :memberships, { mission_attachments: :mission } ])
      .find_by(id: funding_request_id)
    return nil unless funding_request&.approved?
    return nil unless funding_request.owner == current_user
    # Each design kit is claimable once per approved request.
    return nil unless funding_request.redeemable_prize_for(shop_item)

    funding_request
  end

  def load_redeemable_sticky_streak_day(shop_item)
    return nil unless current_user
    day = params[:sticky_streak_day].to_i
    return nil if day.zero?

    sticky_streak = current_user.current_sticky_streak
    # Each day is claimable once, and only for the sticker it was set to.
    return nil unless sticky_streak&.claimable_day?(day)
    return nil unless sticky_streak.rewards_by_day[day]&.shop_item_id == shop_item.id

    StickyStreak::DayClaim.new(sticky_streak: sticky_streak, day: day)
  end
end
