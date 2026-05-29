# == Schema Information
#
# Table name: shop_item_sources
#
#  id             :bigint           not null, primary key
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  shop_item_id   :bigint           not null
#  shop_source_id :bigint           not null
#
# Indexes
#
#  index_shop_item_sources_on_shop_item_id    (shop_item_id)
#  index_shop_item_sources_on_shop_source_id  (shop_source_id)
#  index_shop_item_sources_unique             (shop_item_id,shop_source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (shop_item_id => shop_items.id)
#  fk_rails_...  (shop_source_id => shop_sources.id)
#
class ShopItemSource < ApplicationRecord
  belongs_to :shop_item
  belongs_to :shop_source
end
