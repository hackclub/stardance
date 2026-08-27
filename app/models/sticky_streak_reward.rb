# == Schema Information
#
# Table name: sticky_streak_rewards
#
#  id           :bigint           not null, primary key
#  day_number   :integer          not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  shop_item_id :bigint           not null
#
# Indexes
#
#  index_sticky_streak_rewards_on_day_number    (day_number) UNIQUE
#  index_sticky_streak_rewards_on_shop_item_id  (shop_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (shop_item_id => shop_items.id)
#
class StickyStreakReward < ApplicationRecord
  # Which shop item a Sticky Streak day pays out. Set by shop managers; a day
  # with no row yet shows as a question mark on the board.
  has_paper_trail

  belongs_to :shop_item

  validates :day_number, presence: true,
            uniqueness: true,
            inclusion: { in: 1..StickyStreak::LENGTH }

  scope :ordered, -> { order(:day_number) }

  def self.by_day
    ordered.includes(shop_item: { image_attachment: :blob }).index_by(&:day_number)
  end
end
