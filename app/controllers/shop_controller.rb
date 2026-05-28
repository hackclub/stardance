class ShopController < ApplicationController
  skip_before_action :refresh_identity_on_portal_return, only: [ :index, :category ]

  def index
    prepare_shop_chrome
    load_shop_items
    load_random_items
    load_orders_sidebar
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

  def my_orders
    authorize :shop

    @orders = current_user.shop_orders
                          .where(parent_order_id: nil)
                          .includes(accessory_orders: { shop_item: { image_attachment: :blob } }, shop_item: { image_attachment: :blob })
                          .order(id: :desc)
  end

  def cancel_order
    authorize :shop

    @order = current_user.shop_orders.find(params[:order_id])
    if @order.aasm_state == "fulfilled"
      redirect_to shop_my_orders_path, alert: "You cannot cancel an already fulfilled order."
      return
    end
    result = @order.cancel_by_user

    if result[:success]
      redirect_to shop_my_orders_path, notice: "Order cancelled successfully!"
    else
      redirect_to shop_my_orders_path, alert: "Failed to cancel order: #{result[:error]}"
    end
  end

  def order
    authorize :shop

    @shop_item = ShopItem.find(params[:shop_item_id])
    @mission_submission = load_redeemable_submission(@shop_item)

    if @mission_submission.nil? && @shop_item.mission_prize_only?
      redirect_to shop_path, alert: "This item can only be claimed by redeeming a mission prize."
      return
    end

    unless @shop_item.enabled? || @mission_submission.present?
      redirect_to shop_path, alert: "This item cannot be ordered."
      return
    end

    # TutorialNothing is intentionally `buyable_by_self: false`-friendly in
    # spirit (we don't want it surfacing as a normal item), but we need the
    # buyable check to pass when the user is in the tutorial. Bypass it for
    # the two tutorial items.
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

    @sale_price = @shop_item.price_for_region(@user_region)
    @regional_base_price = @shop_item.base_price_for_region(@user_region)
    @accessories = @shop_item.available_accessories.includes(:image_attachment)

    if @shop_item.requires_achievement?
      @required_achievements = @shop_item.requires_achievement.map { |slug| Achievement.find(slug) }
      @locked_by_achievement = !@shop_item.meet_achievement_require?(current_user)
    end
    ahoy.track "Viewed shop item", shop_item_id: @shop_item.id
  end

  def update_region
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

  def create_order
    authorize :shop

    if current_user.should_reject_orders?
      redirect_to shop_path, alert: "You're not eligible to place orders."
      return
    end

    @shop_item = ShopItem.find(params[:shop_item_id])
    @mission_submission = load_redeemable_submission(@shop_item)

    unless @shop_item.enabled? || @mission_submission.present?
      redirect_to shop_path, alert: "This item cannot be ordered."
      return
    end

    if @mission_submission.nil? && @shop_item.mission_prize_only?
      redirect_to shop_path, alert: "This item can only be claimed by redeeming a mission prize."
      return
    end

    unless @shop_item.buyable_by_self? || tutorial_item?(@shop_item)
      redirect_to shop_path, alert: "This item cannot be ordered on its own."
      return
    end

    quantity = params[:quantity].to_i
    accessory_ids = Array(params[:accessory_ids]).map(&:to_i).reject(&:zero?)

    # Collect accessory IDs from tagged radio buttons (accessory_tag_* params)
    params.each do |key, value|
      if key.to_s.start_with?("accessory_tag_") && value.present?
        accessory_ids << value.to_i
      end
    end
    accessory_ids = accessory_ids.uniq.reject(&:zero?)

    if quantity <= 0
      redirect_to shop_order_path(shop_item_id: @shop_item.id), alert: "Quantity must be greater than 0"
      return
    end

    # Validate accessories belong to this item
    @accessories = if accessory_ids.any?
                     @shop_item.available_accessories.where(id: accessory_ids)
    else
                     []
    end

    # Calculate total cost (applying sale discount via price_for_region)
    # Accessories are multiplied by quantity (e.g., 10 RPis with 8GB RAM = 10 accessories)
    region = user_region
    item_price = @shop_item.price_for_region(region)
    item_total = item_price * quantity
    accessories_total = @accessories.sum { |a| a.price_for_region(region) } * quantity
    total_cost = item_total + accessories_total

    return redirect_to shop_order_path(shop_item_id: @shop_item.id), alert: "You need to have an address to make an order!" unless current_user.addresses.any?

    selected_address = current_user.addresses.find { |a| a["id"] == params[:address_id] } || current_user.addresses.first

    unless selected_address&.dig("phone_number").present? || Rails.env.development? || tutorial_item?(@shop_item)
      return redirect_to shop_order_path(shop_item_id: @shop_item.id), alert: "You need to have a phone number on file to place an order! Please update your profile."
    end

    # Check if item is available in the region of the selected address
    address_country = selected_address&.dig("country")
    address_region = Shop::Regionalizable.country_to_region(address_country)
    unless @shop_item.enabled_in_region?(address_region)
      redirect_to shop_order_path(shop_item_id: @shop_item.id), alert: "This item is not available in your region."
      return
    end

    begin
      ActiveRecord::Base.transaction do
        current_user.lock! # Lock user to prevent race-condition from overspending on user balance
        @shop_item.lock! if @shop_item.limited? # Lock item if limited stock to prevent overselling

        if @mission_submission.nil?
          user_balance = current_user.balance
          if total_cost > user_balance
            redirect_to shop_order_path(shop_item_id: @shop_item.id), alert: "Insufficient balance. You need #{total_cost} Stardust but only have #{user_balance} Stardust."
            return
          end
        end

        @order = current_user.shop_orders.new(
          shop_item: @shop_item,
          quantity: @mission_submission ? 1 : quantity,
          frozen_address: selected_address
        )
        @order.redeeming_mission_submission = @mission_submission if @mission_submission
        @order.aasm_state = "pending" if @order.respond_to?(:aasm_state=)
        @order.save!

        if @mission_submission
          chosen_prize = @mission_submission.mission.prizes.find_by(shop_item_id: @shop_item.id)
          @mission_submission.update!(shop_order_id: @order.id, chosen_prize_id: chosen_prize&.id)
        end

        unless @mission_submission
          @accessories.each do |accessory|
            accessory_order = current_user.shop_orders.new(
              shop_item: accessory,
              quantity: quantity,
              frozen_address: selected_address,
              parent_order_id: @order.id
            )
            accessory_order.aasm_state = "pending" if accessory_order.respond_to?(:aasm_state=)
            accessory_order.save!
          end
        end
      end

      # Mark the tutorial finished as soon as the order is committed. The user
      # picked an item, added an address and clicked Buy — they've done their
      # part. Fulfilment is the system's job and shouldn't gate ship access.
      current_user.mark_shop_tutorial_completed! if tutorial_item?(@shop_item)

      unless current_user.eligible_for_shop?
        @order.queue_for_verification!
        @order.accessory_orders.each(&:queue_for_verification!)
        redirect_to shop_my_orders_path, notice: "Order placed! It will be processed once your identity is verified."
        return
      end

      return if @shop_item.is_a?(ShopItem::FreeStickers) && !fulfill_free_stickers!

      if @shop_item.is_a?(ShopItem::TutorialNothing)
        @shop_item.fulfill!(@order)
        redirect_to shop_my_orders_path, notice: "Nice — that's your first order in! You're ready to ship your first project."
        return
      end

      if @shop_item.is_a?(ShopItem::SillyItemType)
        @order.approve!
        redirect_to shop_my_orders_path, notice: "Order placed and fulfilled!"
        return
      end

      redirect_to shop_my_orders_path, notice: "Order placed successfully!"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to shop_order_path(shop_item_id: @shop_item.id), alert: "Failed to place order: #{e.record.errors.full_messages.join(', ')}"
    end
  end

  private

  # Common chrome variables consumed by both the hub (`index`) and category
  # subpages (`category`) — region, shop open flag, tutorial state.
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
    end

    @categories = Shop::Categorization.all
  end

  # Picks a small randomised subset of the catalogue for the hub's "Discover"
  # row. Excludes unlisted/tutorial items and anything in a region the viewer
  # can't actually order from.
  def load_random_items
    return @random_items = [] if @shop_items.blank?

    pool = @shop_items.select { |item| item.image.attached? && item.enabled_in_region?(@user_region) }

    # In tutorial mode the stickers/nothing picks get their own leading row, so
    # keep them out of the Discover grid below.
    if @shop_mode == :tutorial && @tutorial_items
      pick_ids = @tutorial_items.values.compact.map(&:id).to_set
      pool = pool.reject { |item| pick_ids.include?(item.id) }
    end

    # Discover is a 2-row preview clipped in CSS; "See all" leads to the full
    # listing. Cap the pool so we don't ship a giant hidden grid.
    @random_items = pool.shuffle.first(12)
  end

  # Latest non-cancelled orders for the hub sidebar — keep it tiny.
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

  # `:preview`  — anyone who hasn't earned shop access yet (guests, signed-in
  #               users without a project). They can browse but not buy.
  # `:tutorial` — signed-in user with HCA + ≥1 project who hasn't finished the
  #               shop walkthrough yet. They can interact with the two
  #               tutorial items only.
  # `:normal`   — everyone else. Standard shop behavior.
  def derive_shop_mode
    return :preview if current_user.nil? || current_user.guest?
    return :preview unless current_user.projects.exists?
    return :tutorial if current_user.shop_tutorial_needed?

    :normal
  end

  def load_tutorial_items
    {
      stickers: ShopItem::FreeStickers.where(enabled: true).first,
      nothing:  ShopItem::TutorialNothing.where(enabled: true).first
    }
  end

  def tutorial_item?(shop_item)
    shop_item.is_a?(ShopItem::FreeStickers) || shop_item.is_a?(ShopItem::TutorialNothing)
  end

  # When a user clicks into the tutorial flow, walk them through every
  # prerequisite before showing the normal order page — project → IDV →
  # address. Direct URL access to /shop/order?shop_item_id=X bypasses the
  # shop hub's preview/tutorial gating, so we re-check server-side here.
  # Returns the template name to render, or nil to fall through.
  def required_tutorial_step(shop_item)
    return nil unless current_user
    return nil unless tutorial_item?(shop_item)
    return nil if current_user.shop_tutorial_completed?

    return "shop/tutorial_project" unless current_user.projects.exists?
    return "shop/tutorial_verify"  unless current_user.identity_verified?
    return "shop/tutorial_address" if current_user.addresses.empty?

    nil
  end

  def load_shop_items
    excluded_free_stickers = current_user && has_ordered_free_stickers?
    shop_page_data = ShopItem.cached_shop_page_data
    @shop_items = shop_page_data[:buyable_standalone]
    @shop_items = @shop_items.reject { |item| item.type == "ShopItem::FreeStickers" } if excluded_free_stickers
    @featured_item = featured_free_stickers_item unless excluded_free_stickers
    @recently_added_items = shop_page_data[:recently_added]
    @user_balance = current_user&.cached_balance || 0

    # The cached_shop_page_data stores AR objects post-eager-load, but Rails
    # marshals them through Rails.cache and strips the association cache. On
    # cache hits, the blobs would otherwise N+1 every render. Re-preload them.
    preload_shop_item_images(@shop_items + Array(@recently_added_items) + [ @featured_item ].compact)

    if @shop_mode == :tutorial && @tutorial_items[:nothing].present?
      # TutorialNothing is `unlisted` (so it stays out of the regular shop grid
      # after the tutorial finishes); during the walkthrough we splice it in so
      # the user can interact with it alongside the stickers, and float both
      # tutorial picks to the front of the grid so the spotlight badges land
      # near the page top.
      tutorial_ids = @tutorial_items.values.compact.map(&:id).to_set
      @shop_items = @shop_items + [ @tutorial_items[:nothing] ]
      tutorial_picks, rest = @shop_items.partition { |item| tutorial_ids.include?(item.id) }
      @shop_items = tutorial_picks + rest
    end
  end

  def preload_shop_item_images(items)
    items = items.compact.uniq
    return if items.empty?

    # Preload both the blob and the polymorphic :record back-pointer.
    # Bullet otherwise flags the implicit attachment→record access during
    # URL generation as a missing eager-load, even though `record` resolves
    # to the ShopItem we already have in memory.
    ActiveRecord::Associations::Preloader.new(
      records: items,
      associations: { image_attachment: [ :blob, :record ] }
    ).call
  end

  def has_ordered_free_stickers?
    current_user.has_gotten_free_stickers? ||
      current_user.shop_orders.joins(:shop_item).where(shop_items: { type: "ShopItem::FreeStickers" }).exists?
  end

  def featured_free_stickers_item
    item = ShopItem.find_by(id: 1, type: "ShopItem::FreeStickers", enabled: true)
    item if item&.enabled_in_region?(@user_region)
  end

  def fulfill_free_stickers!
    @shop_item.fulfill!(@order)
    @order.mark_stickers_received
    true
  rescue => e
    Rails.logger.error "Free stickers fulfillment failed: #{e.message}"
    Sentry.capture_exception(e, extra: { order_id: @order.id, user_id: current_user.id })
    redirect_to shop_my_orders_path, alert: "Order placed but fulfillment failed. We'll process it shortly."
    false
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

  # Returns the user's redeemable Mission::Submission if `mission_submission_id`
  # was passed and the submission is approved, owned by the current user,
  # un-redeemed, and offering the given shop_item as a prize. Otherwise nil.
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
