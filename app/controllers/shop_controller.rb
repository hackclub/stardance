class ShopController < ApplicationController
  skip_before_action :refresh_identity_on_portal_return, only: [ :index ]

  def index
    @shop_open = Flipper.enabled?(:shop_open, current_user)
    @user_region = user_region
    @body_class = "shop-page"
    @region_options = Shop::Regionalizable::REGIONS.map do |code, config|
      { label: config[:name], value: code }
    end

    load_shop_items
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

    unless @shop_item.buyable_by_self?
      redirect_to shop_path, alert: "This item cannot be ordered on its own."
      return
    end

    if @mission_submission.nil? && @shop_item.mission_locked_for?(current_user)
      redirect_to shop_path, alert: "This item is locked behind a mission you haven't completed yet."
      return
    end

    @user_region = user_region
    @sale_price = @shop_item.price_for_region(@user_region)
    @regional_base_price = @shop_item.base_price_for_region(@user_region)
    @accessories = @shop_item.available_accessories.includes(:image_attachment)
    @modifiers = @shop_item.available_modifiers_for_region(@user_region)

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

    unless @shop_item.buyable_by_self?
      redirect_to shop_path, alert: "This item cannot be ordered on its own."
      return
    end

    quantity = params[:quantity].to_i
    modifier_ids = Array(params[:modifier_ids]).map(&:to_i).reject(&:zero?)

    # Collect modifier IDs from grouped radio buttons (modifier_group_* params)
    params.each do |key, value|
      if key.to_s.start_with?("modifier_group_") && value.present?
        modifier_ids << value.to_i
      end
    end
    modifier_ids = modifier_ids.uniq.reject(&:zero?)

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

    # Validate modifiers belong to this item and are available in region
    region = user_region
    @modifiers = if modifier_ids.any?
                   @shop_item.available_modifiers_for_region(region).select { |m| modifier_ids.include?(m.id) }
    else
                   []
    end

    # Calculate total cost (applying sale discount via price_for_region)
    # Accessories are multiplied by quantity (e.g., 10 RPis with 8GB RAM = 10 accessories)
    # Modifiers are per-order (not per-unit)
    item_price = @shop_item.price_for_region(region)
    item_total = item_price * quantity
    accessories_total = @accessories.sum { |a| a.price_for_region(region) } * quantity
    modifiers_total = @modifiers.sum { |m| m.price_for_region(region) }
    total_cost = item_total + accessories_total + modifiers_total

    return redirect_to shop_order_path(shop_item_id: @shop_item.id), alert: "You need to have an address to make an order!" unless current_user.addresses.any?

    selected_address = current_user.addresses.find { |a| a["id"] == params[:address_id] } || current_user.addresses.first

    unless selected_address&.dig("phone_number").present? || Rails.env.development? || @shop_item.is_a?(ShopItem::FreeStickers)
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
          frozen_address: selected_address,
          frozen_modifiers_price: @mission_submission ? 0 : modifiers_total
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

          @modifiers.each do |modifier|
            ShopOrderModifierSelection.create!(
              shop_order: @order,
              shop_item_modifier: modifier,
              frozen_modifier_price: modifier.price_for_region(region)
            )
          end
        end
      end

      unless current_user.eligible_for_shop?
        @order.queue_for_verification!
        @order.accessory_orders.each(&:queue_for_verification!)
        redirect_to shop_my_orders_path, notice: "Order placed! It will be processed once your identity is verified."
        return
      end

      return if @shop_item.is_a?(ShopItem::FreeStickers) && !fulfill_free_stickers!

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
