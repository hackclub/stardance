# == Schema Information
#
# Table name: shop_item_modifiers
#
#  id            :bigint           not null, primary key
#  enabled       :boolean          default(TRUE), not null
#  enabled_au    :boolean
#  enabled_ca    :boolean
#  enabled_eu    :boolean
#  enabled_in    :boolean
#  enabled_uk    :boolean
#  enabled_us    :boolean
#  enabled_xx    :boolean
#  group_name    :string
#  name          :string           not null
#  position      :integer          default(0), not null
#  ticket_cost   :integer          default(0), not null
#  usd_cost      :decimal(10, 2)
#  usd_offset_au :decimal(10, 2)
#  usd_offset_ca :decimal(10, 2)
#  usd_offset_eu :decimal(10, 2)
#  usd_offset_in :decimal(10, 2)
#  usd_offset_uk :decimal(10, 2)
#  usd_offset_us :decimal(10, 2)
#  usd_offset_xx :decimal(10, 2)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  shop_item_id  :bigint           not null
#
# Indexes
#
#  index_shop_item_modifiers_on_shop_item_id  (shop_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (shop_item_id => shop_items.id)
#
class ShopItemModifier < ApplicationRecord
  include Shop::Regionalizable

  belongs_to :shop_item
  has_one_attached :image
  has_many :shop_order_modifier_selections, dependent: :destroy

  validates :name, presence: true
  validates :ticket_cost, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :globally_enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }

  def hacker_score
    shop_item&.hacker_score
  end

  def sale_percentage
    nil
  end

  def available_in_region?(region_code)
    enabled? && enabled_in_region?(region_code)
  end

  def free?
    price_for_region("XX").zero?
  end
end
