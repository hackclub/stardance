class Shop::OrdersController < Shop::BaseController
  before_action :require_login

  def index
    @orders = current_user.shop_orders
                          .where(parent_order_id: nil)
                          .includes(accessory_orders: { shop_item: { image_attachment: :blob } }, shop_item: { image_attachment: :blob })
                          .order(id: :desc)
    @show_tutorial_complete_dialog = session.delete(:show_tutorial_complete_dialog)
  end

  def create
    if current_user.should_reject_orders?
      redirect_to shop_items_path, alert: "You're not eligible to place orders."
      return
    end

    @shop_item = ShopItem.enabled.find(params[:shop_item_id])
    unless @shop_item.present?
      redirect_to shop_items_path, alert: "This item cannot be ordered."
      return
    end
    unless @shop_item.buyable_by_self?
      redirect_to shop_items_path, alert: "This item cannot be ordered on its own."
      return
    end

    quantity = params[:quantity].to_i
    accessory_ids = Array(params[:accessory_ids]).map(&:to_i).reject(&:zero?)

    params.each do |key, value|
      if key.to_s.start_with?("accessory_tag_") && value.present?
        accessory_ids << value.to_i
      end
    end
    accessory_ids = accessory_ids.uniq.reject(&:zero?)

    if quantity <= 0
      redirect_to shop_item_path(@shop_item), alert: "Quantity must be greater than 0"
      return
    end

    @accessories = if accessory_ids.any?
                     @shop_item.available_accessories.where(id: accessory_ids)
    else
                     []
    end

    region = user_region
    item_price = @shop_item.price_for_region(region)
    item_total = item_price * quantity
    accessories_total = @accessories.sum { |a| a.price_for_region(region) } * quantity
    total_cost = item_total + accessories_total

    return redirect_to shop_item_path(@shop_item), alert: "You need to have an address to make an order!" unless current_user.addresses.any?

    selected_address = current_user.addresses.find { |a| a["id"] == params[:address_id] } || current_user.addresses.first

    unless selected_address&.dig("phone_number").present? || Rails.env.development? || @shop_item.is_a?(ShopItem::FreeStickers)
      return redirect_to shop_item_path(@shop_item), alert: "You need to have a phone number on file to place an order! Please update your profile."
    end

    address_country = selected_address&.dig("country")
    address_region = Shop::Regionalizable.country_to_region(address_country)
    unless @shop_item.enabled_in_region?(address_region)
      redirect_to shop_item_path(@shop_item), alert: "This item is not available in your region."
      return
    end

    begin
      ActiveRecord::Base.transaction do
        current_user.lock!
        user_balance = current_user.balance

        if total_cost > user_balance
          redirect_to shop_item_path(@shop_item), alert: "Insufficient balance. You need 🍪#{total_cost} but only have 🍪#{user_balance}."
          return
        end

        @order = current_user.shop_orders.new(
          shop_item: @shop_item,
          quantity: quantity,
          frozen_address: selected_address,
          accessory_ids: @accessories.pluck(:id)
        )
        @order.aasm_state = "pending" if @order.respond_to?(:aasm_state=)
        @order.save!

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

      handle_free_stickers_order! if @shop_item.is_a?(ShopItem::FreeStickers)

      unless current_user.eligible_for_shop?
        @order.queue_for_verification!
        @order.accessory_orders.each(&:queue_for_verification!)
        redirect_to shop_orders_path, notice: "Order placed! It will be processed once your identity is verified."
        return
      end

      return if @shop_item.is_a?(ShopItem::FreeStickers) && !fulfill_free_stickers!

      if @shop_item.is_a?(ShopItem::SillyItemType)
        @order.approve!
        redirect_to shop_orders_path, notice: "Order placed and fulfilled!"
        return
      end

      redirect_to shop_orders_path, notice: "Order placed successfully!"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to shop_item_path(@shop_item), alert: "Failed to place order: #{e.record.errors.full_messages.join(', ')}"
    end
  end

  def cancel
    @order = current_user.shop_orders.find(params[:id])
    if @order.aasm_state == "fulfilled"
      redirect_to shop_orders_path, alert: "You cannot cancel an already fulfilled order."
      return
    end
    result = current_user.cancel_shop_order(params[:id])

    if result[:success]
      redirect_to shop_orders_path, notice: "Order cancelled successfully!"
    else
      redirect_to shop_orders_path, alert: "Failed to cancel order: #{result[:error]}"
    end
  end

  private

  def handle_free_stickers_order!
    current_user.complete_tutorial_step!(:free_stickers)
    session.delete(:tutorial_redirect_url)
    session[:show_tutorial_complete_dialog] = true
  end

  def fulfill_free_stickers!
    @shop_item.fulfill!(@order)
    @order.mark_stickers_received
    true
  rescue => e
    Rails.logger.error "Free stickers fulfillment failed: #{e.message}"
    Sentry.capture_exception(e, extra: { order_id: @order.id, user_id: current_user.id })
    redirect_to shop_orders_path, alert: "Order placed but fulfillment failed. We'll process it shortly."
    false
  end
end
