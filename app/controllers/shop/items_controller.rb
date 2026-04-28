class Shop::ItemsController < Shop::BaseController
  skip_before_action :refresh_identity_on_portal_return, only: [ :index ]

  def index
    @shop_open = Flipper.enabled?(:shop_open, current_user)
    @user_region = user_region
    @body_class = "shop-page"
    @region_options = Shop::Regionalizable::REGIONS.map do |code, config|
      { label: config[:name], value: code }
    end

    if current_user
      free_stickers_step = User::TutorialStep.find(:free_stickers)
      @show_shop_tutorial = free_stickers_step.deps_satisfied?(current_user.tutorial_steps) &&
                            !current_user.tutorial_step_completed?(:free_stickers)

      grant_free_stickers_welcome_cookies! if @show_shop_tutorial
    else
      @show_shop_tutorial = false
    end

    load_shop_items
  end

  def show
    require_login
    @shop_item = ShopItem.enabled.find(params[:id])

    unless @shop_item.buyable_by_self?
      redirect_to shop_items_path, alert: "This item cannot be ordered on its own."
      return
    end

    @user_region = user_region
    @sale_price = @shop_item.price_for_region(@user_region)
    @regional_base_price = @shop_item.base_price_for_region(@user_region)
    @accessories = @shop_item.available_accessories.includes(:image_attachment)

    if @shop_item.requires_achievement?
      @required_achievements = @shop_item.requires_achievement.map { |slug| Achievement.find(slug) }
      @locked_by_achievement = !@shop_item.meet_achievement_require?(current_user)
    end
    ahoy.track "Viewed shop item", shop_item_id: @shop_item.id
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

  def grant_free_stickers_welcome_cookies!
    unless current_user.ledger_entries.exists?(reason: "Free Stickers Welcome Grant")
      current_user.ledger_entries.create!(
        amount: 10, reason: "Free Stickers Welcome Grant", created_by: "System", ledgerable: current_user
      )
    end
    order_url = shop_item_url(1)
    session[:tutorial_redirect_url] = HCAService.address_portal_url(return_to: order_url)
  end
end
