class Shop::ItemsController < Shop::BaseController
  skip_before_action :refresh_identity_on_portal_return, only: [ :index, :category ]

  discover_rail_widgets :shop_orders, :shop_updates, :shop_wishlist,
    context: -> { { sidebar_orders: @sidebar_orders || [], user_balance: @user_balance || 0 } }

  def index
    if params[:q].present?
      redirect_to shop_category_path("all", q: params[:q])
      return
    end

    prepare_shop_chrome
    load_shop_items
    load_hub_sections
    load_orders_sidebar
  end

  def show
    authorize :shop

    @shop_item = ShopItem.find(params[:id])
    @mission_submission = load_redeemable_submission(@shop_item)

    if @mission_submission.nil? && @shop_item.mission_prize_only?
      redirect_to shop_path, alert: "This item can only be claimed by redeeming a mission prize."
      return
    end

    unless @shop_item.enabled? || @mission_submission.present?
      redirect_to shop_path, alert: "This item cannot be ordered."
      return
    end

    unless @shop_item.buyable_by_self? || tutorial_item?(@shop_item)
      redirect_to shop_path, alert: "This item cannot be ordered on its own."
      return
    end

    if @mission_submission.nil? && @shop_item.mission_locked_for?(current_user)
      redirect_to shop_path, alert: "This item is locked behind a mission you haven't completed yet."
      return
    end

    @user_region = user_region

    if tutorial_step = required_tutorial_step(@shop_item)
      render tutorial_step, layout: "application"
      return
    end

    @sale_price = @shop_item.price_for_user(current_user, @user_region)
    @regional_base_price = @shop_item.base_price_for_region(@user_region)
    @accessories = @shop_item.available_accessories.includes(:image_attachment)
    @modifiers = @shop_item.available_modifiers_for_region(@user_region)

    if @shop_item.requires_achievement?
      @required_achievements = @shop_item.requires_achievement.map { |slug| Achievement.find(slug) }
      @locked_by_achievement = !@shop_item.meet_achievement_require?(current_user)
    end
    track_event "Viewed shop item", shop_item_id: @shop_item.id
  end

  def category
    @slug = params[:slug].to_s
    @category = Shop::Categorization.find(@slug)
    raise ActiveRecord::RecordNotFound unless @category

    @category_title = @category.title
    @category_hub_title = @category.hub_title

    prepare_shop_chrome
    load_shop_items
    @shop_items = Shop::Categorization.filter(@shop_items, @slug)
  end

  private

  def prepare_shop_chrome
    @shop_open = Flipper.enabled?(:shop_open, current_user)
    @user_region = user_region
    @body_class = "shop-page"
    @region_options = Shop::Regionalizable::REGIONS.map do |code, config|
      { label: config[:name], value: code }
    end

    @shop_mode = derive_shop_mode
    if @shop_mode == :tutorial
      @tutorial_items = load_tutorial_items
      current_user&.mark_shop_tutorial_started!
    elsif @shop_mode == :preview
      @preview_tutorial_items = load_tutorial_items
    end

    @categories = Shop::Categorization.all
    @wishlisted_item_ids = current_user&.shop_wishlists&.pluck(:shop_item_id) || []
  end

  def load_hub_sections
    @new_items = []
    @popular_items = []
    return if @shop_items.blank?

    pool = @shop_items.select { |item| item.image.attached? && item.enabled_in_region?(@user_region) }

    shuffled = pool.shuffle
    @new_items     = shuffled.first(8)
    @popular_items = shuffled.drop(8).first(8)
  end

  def load_orders_sidebar
    @sidebar_orders = if current_user
                        current_user.shop_orders
                                    .where(parent_order_id: nil)
                                    .includes(shop_item: { image_attachment: :blob })
                                    .order(id: :desc)
                                    .limit(3)
    else
                        []
    end
  end

  def required_tutorial_step(shop_item)
    return nil unless current_user
    return nil unless tutorial_item?(shop_item)
    return nil if current_user.shop_tutorial_completed?

    return "shop/items/tutorial_project" unless current_user.projects.exists?
    return "shop/items/tutorial_verify"  unless current_user.identity_submitted?
    return "shop/items/tutorial_address" if current_user.addresses.empty?

    nil
  end
end
