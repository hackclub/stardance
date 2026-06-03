# frozen_string_literal: true

# == Schema Information
#
# Table name: shop_wishlists
#
#  id           :bigint           not null, primary key
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  shop_item_id :bigint           not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_shop_wishlists_on_shop_item_id              (shop_item_id)
#  index_shop_wishlists_on_user_id                   (user_id)
#  index_shop_wishlists_on_user_id_and_shop_item_id  (user_id,shop_item_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (shop_item_id => shop_items.id)
#  fk_rails_...  (user_id => users.id)
#
class ShopWishlist < ApplicationRecord
  belongs_to :user
  belongs_to :shop_item

  validates :shop_item_id, uniqueness: { scope: :user_id }
end
