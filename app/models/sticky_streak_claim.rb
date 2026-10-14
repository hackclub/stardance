# == Schema Information
#
# Table name: sticky_streak_claims
#
#  id               :bigint           not null, primary key
#  day_number       :integer          not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  shop_order_id    :bigint           not null
#  sticky_streak_id :bigint           not null
#
# Indexes
#
#  index_sticky_streak_claims_on_shop_order_id                    (shop_order_id) UNIQUE
#  index_sticky_streak_claims_on_sticky_streak_id                 (sticky_streak_id)
#  index_sticky_streak_claims_on_sticky_streak_id_and_day_number  (sticky_streak_id,day_number) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (shop_order_id => shop_orders.id)
#  fk_rails_...  (sticky_streak_id => sticky_streaks.id)
#
class StickyStreakClaim < ApplicationRecord
  # One redeemed Sticky Streak day, pointing at the free order it placed.
  has_paper_trail

  belongs_to :sticky_streak
  belongs_to :shop_order

  validates :day_number, presence: true,
            uniqueness: { scope: :sticky_streak_id },
            inclusion: { in: 1..StickyStreak::LENGTH }
  validates :shop_order_id, uniqueness: true
end
