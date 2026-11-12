# Fulfilment endpoints for tools acting on a staff member's behalf, e.g. an
# assistant that reads carrier emails and sets tracking. Authenticates with the
# staff member's personal API key (account settings) and is limited to the
# same people who can set tracking from the admin order page. Order responses
# carry no address or other buyer details; the address has its own endpoint,
# which applies the admin page's per-order check and is audit logged.
#
#   # Find orders whose external_ref or tracking contains a store order number
#   curl -H "Authorization: Bearer $STARDANCE_API_KEY" \
#     "https://stardance.hackclub.com/api/v1/shop_orders?query=AU787303367675330561"
#
#   # Fetch one order
#   curl -H "Authorization: Bearer $STARDANCE_API_KEY" \
#     https://stardance.hackclub.com/api/v1/shop_orders/123
#
#   # Read the order's shipping address (audit logged like "Reveal address")
#   curl -H "Authorization: Bearer $STARDANCE_API_KEY" \
#     https://stardance.hackclub.com/api/v1/shop_orders/123/address
#
#   # Set or change tracking (the buyer is DMed; an empty value clears it)
#   curl -X PATCH -H "Authorization: Bearer $STARDANCE_API_KEY" \
#     -H "Content-Type: application/json" -d '{"tracking_number":"1Z999AA10123456784"}' \
#     https://stardance.hackclub.com/api/v1/shop_orders/123
#
#   # Mark an order that is awaiting fulfilment as fulfilled. Every field is
#   # optional, as on the admin page; the buyer gets the usual fulfilled notice.
#   curl -X POST -H "Authorization: Bearer $STARDANCE_API_KEY" \
#     -H "Content-Type: application/json" \
#     -d '{"external_ref":"Amazon 113-1234567","fulfillment_cost":"24.99","tracking_number":"1Z999AA10123456784"}' \
#     https://stardance.hackclub.com/api/v1/shop_orders/123/fulfill
class Api::V1::ShopOrdersController < Api::V1::PublicApiController
  before_action :require_fulfillment_access!
  before_action :set_order, only: [ :show, :update, :address, :fulfill ]

  def index
    return render json: { error: "query is required" }, status: :bad_request if params[:query].blank?

    pattern = "%#{ShopOrder.sanitize_sql_like(params[:query].strip)}%"
    scope = ShopOrder.preload(:shop_item)
                     .where("external_ref ILIKE :pattern OR tracking_number ILIKE :pattern", pattern: pattern)
                     .order(id: :desc)

    @pagy, @orders = pagy(:offset, scope, **pagination_options)
  end

  def show
  end

  def update
    return render json: { error: "tracking_number is required" }, status: :bad_request unless params.key?(:tracking_number)

    updated = PaperTrail.request(whodunnit: current_api_user.id) do
      @order.update_tracking(params[:tracking_number], by: current_api_user)
    end

    if updated
      render :show
    else
      render json: { error: @order.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # Mirrors the admin order page's "Reveal address": the same per-order check
  # (regions, digital items) and the same two audit records.
  def address
    unless @order.can_view_address?(current_api_user)
      return render json: { error: "You can't view this order's address" }, status: :forbidden
    end

    address = @order.decrypted_address_for(current_api_user)

    ::PaperTrail::Version.create!(
      item_type: "User",
      item_id: @order.user_id,
      event: "address_revealed",
      whodunnit: current_api_user.id.to_s,
      object_changes: { order_id: @order.id, shop_item: @order.shop_item&.name, via: "api" }
    )

    render json: { id: @order.id, address: address }
  end

  # Mirrors the admin order page's "Mark as Fulfilled" form, limited to orders
  # awaiting fulfilment so a tool can't fulfil a pending, held or refunded one.
  def fulfill
    unless @order.awaiting_periodical_fulfillment?
      return render json: { error: "Only orders awaiting fulfillment can be marked fulfilled" }, status: :unprocessable_entity
    end

    cost = params[:fulfillment_cost].presence
    if cost && !non_negative_number?(cost)
      return render json: { error: "fulfillment_cost must be a non-negative number" }, status: :bad_request
    end

    old_state = @order.aasm_state
    fulfilled = PaperTrail.request(whodunnit: current_api_user.id) do
      @order.mark_fulfilled(params[:external_ref].presence, cost, current_api_user.display_name, params[:tracking_number]) && @order.save
    end

    if fulfilled
      ::PaperTrail::Version.create!(
        item_type: "ShopOrder",
        item_id: @order.id,
        event: "update",
        whodunnit: current_api_user.id,
        object_changes: { aasm_state: [ old_state, @order.aasm_state ] }
      )
      render :show
    else
      render json: { error: @order.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private
    def require_fulfillment_access!
      return if ::Admin::ShopOrderPolicy.new(current_api_user, ShopOrder).update_tracking?

      render json: { error: "Fulfillment access required" }, status: :forbidden
    end

    def set_order
      @order = ShopOrder.preload(:shop_item).find(params[:id])
    end

    def non_negative_number?(value)
      BigDecimal(value.to_s) >= 0
    rescue ArgumentError, TypeError
      false
    end
end
