module Seller
  class OrdersController < ApplicationController
    before_action :set_paper_trail_whodunnit
    before_action -> { authorize :seller, :access? }
    before_action :set_order, only: %i[show reveal_address mark_fulfilled]

    def index
      orders = seller_orders.includes(:shop_item, :user)

      orders = case params[:status]
      when "fulfilled" then orders.where(aasm_state: "fulfilled")
      when "awaiting" then orders.where(aasm_state: "awaiting_periodical_fulfillment")
      else orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment awaiting_verification])
      end

      @items = current_user.sold_items.order(:name)
      orders = orders.where(shop_item_id: params[:item_id]) if params[:item_id].present?

      @c = %w[pending awaiting_periodical_fulfillment fulfilled].index_with { |s| seller_orders.where(aasm_state: s).count }
      @pagy, @orders = pagy(:offset, orders.order(created_at: :desc), limit: 25)
    end

    def show; end

    def reveal_address
      unless @order.can_view_address?(current_user)
        render plain: "no", status: :forbidden and return
      end

      a = @order.decrypted_address_for(current_user)
      audit!("User", @order.user_id, "address_revealed", order_id: @order.id, shop_item: @order.shop_item&.name)

      render turbo_stream: turbo_stream.replace(
        "address-content",
        partial: "admin/shop_orders/address_details",
        locals: { address: a, user_email: @order.user.email }
      )
    end

    def mark_fulfilled
      unless @order.awaiting_periodical_fulfillment?
        redirect_to seller_order_path(@order), alert: "Order is not ready for fulfillment" and return
      end

      old = @order.aasm_state
      if @order.mark_fulfilled(params[:external_ref].presence, params[:fulfillment_cost].presence, "#{current_user.display_name} (seller)", params[:tracking_number]) && @order.save
        audit!("ShopOrder", @order.id, "update", aasm_state: [ old, @order.aasm_state ])
        redirect_to seller_order_path(@order), notice: "Order marked as fulfilled"
      else
        redirect_to seller_order_path(@order), alert: "Failed: #{@order.errors.full_messages.join(', ')}"
      end
    end

    private

    def seller_orders
      ShopOrder.joins(:shop_item).where(shop_items: { user_id: current_user.id, type: "ShopItem::HackClubberItem" })
    end

    def set_order
      @order = seller_orders.includes(:shop_item, :user).find(params[:id])
    end

    def audit!(type, id, event, **changes)
      PaperTrail::Version.create!(
        item_type: type, item_id: id, event: event,
        whodunnit: current_user.id.to_s,
        object_changes: changes.merge(context: "seller_portal")
      )
    end
  end
end
