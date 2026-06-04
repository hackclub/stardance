class Api::V1::Users::Me::OrdersController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    orders = current_api_user.shop_orders
                             .where(parent_order_id: nil)
                             .includes(shop_item: { image_attachment: :blob })
                             .order(id: :desc)
    @pagy, @orders = pagy(orders, limit: limit)
    render "api/v1/orders/index"
  end

  def show
    @order = current_api_user.shop_orders.find(params[:id])
    render "api/v1/orders/show"
  end
end
