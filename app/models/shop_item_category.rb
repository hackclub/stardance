# == Schema Information
#
# Table name: shop_item_categories
#
#  id               :bigint           not null, primary key
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  shop_category_id :bigint           not null
#  shop_item_id     :bigint           not null
#
# Indexes
#
#  index_shop_item_categories_on_shop_category_id  (shop_category_id)
#  index_shop_item_categories_on_shop_item_id      (shop_item_id)
#  index_shop_item_categories_unique               (shop_item_id,shop_category_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (shop_category_id => shop_categories.id)
#  fk_rails_...  (shop_item_id => shop_items.id)
#
class ShopItemCategory < ApplicationRecord
  belongs_to :shop_item
  belongs_to :shop_category
end
