json.extract! shop_order, :id, :aasm_state, :external_ref, :tracking_number, :fulfilled_at, :region
json.item_name shop_order.shop_item.name
