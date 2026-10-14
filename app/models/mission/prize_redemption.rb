# == Schema Information
#
# Table name: mission_prize_redemptions
#
#  id               :bigint           not null, primary key
#  source_type      :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  mission_id       :bigint           not null
#  mission_prize_id :bigint           not null
#  shop_order_id    :bigint           not null
#  source_id        :bigint           not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_mission_prize_redemptions_on_mission_id        (mission_id)
#  index_mission_prize_redemptions_on_mission_prize_id  (mission_prize_id)
#  index_mission_prize_redemptions_on_shop_order_id     (shop_order_id) UNIQUE
#  index_mission_prize_redemptions_on_source            (source_type,source_id)
#  index_mission_prize_redemptions_on_user_id           (user_id)
#  index_prize_redemptions_on_source_and_prize          (source_type,source_id,mission_prize_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (mission_prize_id => mission_prizes.id)
#  fk_rails_...  (shop_order_id => shop_orders.id)
#  fk_rails_...  (user_id => users.id)
#
class Mission::PrizeRedemption < ApplicationRecord
  self.table_name = "mission_prize_redemptions"

  has_paper_trail

  belongs_to :user
  belongs_to :mission
  belongs_to :mission_prize, class_name: "Mission::Prize", inverse_of: :redemptions
  belongs_to :shop_order
  # Gate that unlocked the redemption: a Certification::FundingRequest (after_design)
  # or a Mission::Submission (after_shipping).
  belongs_to :source, polymorphic: true

  validates :shop_order_id, uniqueness: true
  validates :source_id, uniqueness: { scope: [ :source_type, :mission_prize_id ] }

  # Records a redemption for a freshly-placed free order. `gate` is the approval
  # that unlocked it (a Mission::Submission or Certification::FundingRequest) and
  # answers `redeemable_prize_for`. Submissions keep their inline link populated
  # until that column is retired; it points at the first claim, since a gate can
  # now redeem every prize in its category. Returns the redemption, or nil if the
  # item is not a claimable prize on the gate's mission.
  def self.record!(shop_order:, gate:)
    prize = gate.redeemable_prize_for(shop_order.shop_item)
    return unless prize

    redemption = create!(
      user: shop_order.user,
      mission: prize.mission,
      mission_prize: prize,
      shop_order: shop_order,
      source: gate
    )
    if gate.is_a?(Mission::Submission) && gate.shop_order_id.nil?
      gate.update!(shop_order_id: shop_order.id, chosen_prize_id: prize.id)
    end
    redemption
  end
end
