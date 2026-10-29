json.shop_orders @orders do |shop_order|
  json.partial! "api/v1/shop_orders/shop_order", shop_order: shop_order
end

json.partial! "api/v1/pagination", pagy: @pagy
