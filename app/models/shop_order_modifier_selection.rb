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
class ShopOrderModifierSelection < ApplicationRecord
  belongs_to :shop_order
  belongs_to :shop_item_modifier
end
