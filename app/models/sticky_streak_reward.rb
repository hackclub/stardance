# == Schema Information
#
# Table name: sticky_streak_rewards
#
#  id           :bigint           not null, primary key
#  day_number   :integer          not null
#  track        :string           default("standard"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  shop_item_id :bigint           not null
#
# Indexes
#
#  index_sticky_streak_rewards_on_shop_item_id          (shop_item_id)
#  index_sticky_streak_rewards_on_track_and_day_number  (track,day_number) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (shop_item_id => shop_items.id)
#
class StickyStreakReward < ApplicationRecord
  # Which shop item a Sticky Streak day pays out. Set by shop managers; a day
  # with no row yet shows as a question mark on the board. First runs and
  # restarts share the standard track, while second streaks have their own and
  # only pay out on StickyStreak::SECOND_REWARD_DAYS.
  has_paper_trail

  # Prefixed because "second" is an ActiveRecord finder.
  enum :track, { standard: "standard", second: "second" }, prefix: true

  belongs_to :shop_item

  validates :day_number, presence: true, uniqueness: { scope: :track }
  validate :day_number_pays_out_on_track

  scope :ordered, -> { order(:day_number) }

  def self.by_day(track = :standard)
    where(track: track).ordered.includes(shop_item: { image_attachment: :blob }).index_by(&:day_number)
  end

  private

  def day_number_pays_out_on_track
    return if day_number.blank?
    return if StickyStreak.reward_days_for(track).include?(day_number)

    errors.add(:day_number, "is not a reward day on the #{track} track")
  end
end
