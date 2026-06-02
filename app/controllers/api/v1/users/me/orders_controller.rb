class Api::V1::Users::Me::OrdersController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    orders = current_api_user.shop_orders
                             .where(parent_order_id: nil)
                             .includes(shop_item: { image_attachment: :blob })
                             .order(id: :desc)
    @pagy, @orders = pagy(orders, limit: limit)
  end

  def show
    @order = current_api_user.shop_orders.find(params[:id])
  end
end
