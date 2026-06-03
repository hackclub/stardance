json.shop_items @items, partial: "api/v1/shop_items/shop_item", as: :item, locals: { user_region: @user_region }
json.pagination { json.partial! "api/v1/pagination", pagy: @pagy }
