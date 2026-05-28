# == Schema Information
#
# Table name: shop_sources
#
#  id         :bigint           not null, primary key
#  position   :integer          default(0), not null
#  slug       :string           not null
#  title      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_shop_sources_on_position  (position)
#  index_shop_sources_on_slug      (slug) UNIQUE
#
class ShopSource < ApplicationRecord
  has_many :shop_item_sources, dependent: :destroy
  has_many :shop_items, through: :shop_item_sources

  validates :slug, :title, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/, message: "must be lowercase letters, numbers, or underscores" }

  scope :ordered, -> { order(:position, :id) }
end
