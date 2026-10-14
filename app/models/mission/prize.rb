# == Schema Information
#
# Table name: mission_prizes
#
#  id           :bigint           not null, primary key
#  category     :integer          default(0), not null
#  deleted_at   :datetime
#  position     :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  mission_id   :bigint           not null
#  shop_item_id :bigint           not null
#
# Indexes
#
#  index_mission_prizes_active_unique    (mission_id,shop_item_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_mission_prizes_on_deleted_at    (deleted_at)
#  index_mission_prizes_on_mission_id    (mission_id)
#  index_mission_prizes_on_shop_item_id  (shop_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (shop_item_id => shop_items.id)
#
class Mission::Prize < ApplicationRecord
  self.table_name = "mission_prizes"

  include SoftDeletable

  has_paper_trail

  belongs_to :mission, inverse_of: :prizes, counter_cache: true
  belongs_to :shop_item
  has_many :redemptions, class_name: "Mission::PrizeRedemption", inverse_of: :mission_prize, dependent: :destroy

  # after_shipping is the historical default (redeemed once a ship is approved);
  # after_design gates a kit on funding/design approval.
  enum :category, { after_shipping: 0, after_design: 1 }, default: :after_shipping

  # Admin-facing label for each category (mission prize editor).
  CATEGORY_LABELS = { "after_design" => "After design", "after_shipping" => "After shipping" }.freeze

  validates :position, presence: true, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :id) }
end
