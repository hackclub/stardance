class Shop::Orders::FlexImagesController < Shop::BaseController
  def show
    head :not_found and return unless Flipper.enabled?(:sharable_purchase, current_user)

    authorize :shop, :flex_image?
    order = current_user.shop_orders.find(params[:order_id])

    png_data = OgImage::ShopOrderFlex.new(order).to_png

    expires_in 30.minutes, public: false
    if params[:download].present?
      send_data png_data, type: "image/png", disposition: "attachment", filename: "stardance-order-#{order.id}.png"
    else
      send_data png_data, type: "image/png", disposition: "inline"
    end
  end
end
