class Shop::OrdersController < Shop::BaseController
  def index
    authorize :shop

    @orders = current_user.shop_orders
                          .where(parent_order_id: nil)
                          .includes(accessory_orders: { shop_item: { image_attachment: :blob } }, shop_item: { image_attachment: :blob })
                          .order(id: :desc)
  end

  def create
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
    modifier_ids = Array(params[:modifier_ids]).map(&:to_i).reject(&:zero?)

    params.each do |key, value|
      if key.to_s.start_with?("modifier_group_") && value.present?
        modifier_ids << value.to_i
      end
    end
    modifier_ids = modifier_ids.uniq.reject(&:zero?)

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
    @modifiers = if modifier_ids.any?
                   @shop_item.available_modifiers_for_region(region).select { |m| modifier_ids.include?(m.id) }
    else
                   []
    end

    item_price = @shop_item.price_for_user(current_user, region)
    item_total = item_price * quantity
    accessories_total = @accessories.sum { |a| a.price_for_region(region) } * quantity
    modifiers_total = @modifiers.sum { |m| m.price_for_region(region) }
    total_cost = item_total + accessories_total + modifiers_total

    return redirect_to shop_item_path(@shop_item), alert: "You need to have an address to make an order!" unless current_user.addresses.any?

    selected_address = current_user.addresses.find { |a| a["id"] == params[:address_id] } || current_user.addresses.first

    unless selected_address&.dig("phone_number").present? || Rails.env.development? || tutorial_item?(@shop_item)
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
        @shop_item.lock! if @shop_item.limited?

        if @mission_submission.nil?
          user_balance = current_user.balance
          if total_cost > user_balance
            redirect_to shop_item_path(@shop_item), alert: "Insufficient balance. You need #{total_cost} Stardust but only have #{user_balance} Stardust."
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

      track_event "order_placed", { order_id: @order.id, shop_item_id: @shop_item.id, total_cost: total_cost }
      current_user.mark_shop_tutorial_completed! if tutorial_item?(@shop_item)

      if @shop_item.is_a?(ShopItem::TutorialNothing)
        @shop_item.fulfill!(@order)
        redirect_to shop_orders_path, notice: "Nice — that's your first order in! You're ready to ship your first project."
        return
      end

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
    authorize :shop

    @order = current_user.shop_orders.find(params[:id])
    if @order.shop_item.is_a?(ShopItem::FreeStickers)
      redirect_to shop_orders_path, alert: "Free sticker orders cannot be cancelled."
      return
    end
    if @order.aasm_state == "fulfilled"
      redirect_to shop_orders_path, alert: "You cannot cancel an already fulfilled order."
      return
    end
    result = @order.cancel_by_user

    if result[:success]
      redirect_to shop_orders_path, notice: "Order cancelled successfully!"
    else
      redirect_to shop_orders_path, alert: "Failed to cancel order: #{result[:error]}"
    end
  end

  private

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
