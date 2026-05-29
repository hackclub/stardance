# == Schema Information
#
# Table name: shop_order_modifier_selections
#
#  id                    :bigint           not null, primary key
#  frozen_modifier_price :integer          default(0), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  shop_item_modifier_id :bigint           not null
#  shop_order_id         :bigint           not null
#
# Indexes
#
#  idx_modifier_selections_unique                                 (shop_order_id,shop_item_modifier_id) UNIQUE
#  index_shop_order_modifier_selections_on_shop_item_modifier_id  (shop_item_modifier_id)
#  index_shop_order_modifier_selections_on_shop_order_id          (shop_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (shop_item_modifier_id => shop_item_modifiers.id)
#  fk_rails_...  (shop_order_id => shop_orders.id)
#
class ShopOrderModifierSelection < ApplicationRecord
  belongs_to :shop_order
  belongs_to :shop_item_modifier
end
