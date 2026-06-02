json.extract! order, :id, :aasm_state, :quantity, :frozen_item_price, :rejection_reason,
              :tracking_number, :fulfilled_at, :created_at, :updated_at

json.item do
  json.id order.shop_item.id
  json.name order.shop_item.name
  json.image_url order.shop_item.image.attached? ? rails_blob_path(order.shop_item.image, only_path: true) : nil
end
