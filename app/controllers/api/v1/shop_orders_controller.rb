# Fulfilment endpoints for tools acting on a staff member's behalf, e.g. an
# assistant that reads carrier emails and sets tracking. Authenticates with the
# staff member's personal API key (account settings) and is limited to the
# same people who can set tracking from the admin order page. Responses carry
# no address or other buyer details.
#
#   # Find orders whose external_ref or tracking contains a store order number
#   curl -H "Authorization: Bearer $STARDANCE_API_KEY" \
#     "https://stardance.hackclub.com/api/v1/shop_orders?query=AU787303367675330561"
#
#   # Fetch one order
#   curl -H "Authorization: Bearer $STARDANCE_API_KEY" \
#     https://stardance.hackclub.com/api/v1/shop_orders/123
#
#   # Set or change tracking (the buyer is DMed; an empty value clears it)
#   curl -X PATCH -H "Authorization: Bearer $STARDANCE_API_KEY" \
#     -H "Content-Type: application/json" -d '{"tracking_number":"1Z999AA10123456784"}' \
#     https://stardance.hackclub.com/api/v1/shop_orders/123
class Api::V1::ShopOrdersController < Api::V1::PublicApiController
  before_action :require_fulfillment_access!
  before_action :set_order, only: [ :show, :update ]

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

  private
    def require_fulfillment_access!
      return if ::Admin::ShopOrderPolicy.new(current_api_user, ShopOrder).update_tracking?

      render json: { error: "Fulfillment access required" }, status: :forbidden
    end

    def set_order
      @order = ShopOrder.preload(:shop_item).find(params[:id])
    end
end
