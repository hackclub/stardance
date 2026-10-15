# The redemption-gate interface shared by the two records that unlock mission
# prizes: a Mission::Submission (after shipping) and a
# Certification::FundingRequest (after design). A gate unlocks every prize in
# its category, one order each, so the claim stays open until they are all
# redeemed.
#
# Includers define `redemption_mission` and `redemption_prize_category`.
module Mission::PrizeRedeemable
  extend ActiveSupport::Concern

  included do
    has_many :prize_redemptions, class_name: "Mission::PrizeRedemption",
             as: :source, dependent: :destroy, inverse_of: :source
  end

  # Every prize this gate unlocks, in display order.
  def redeemable_prizes
    return Mission::Prize.none unless redemption_mission

    redemption_mission.prizes
      .where(category: redemption_prize_category)
      .ordered
      .includes(:shop_item)
  end

  # The ones still to claim.
  def unredeemed_prizes
    redeemable_prizes.where.not(id: prize_redemptions.select(:mission_prize_id))
  end

  def prizes_to_claim?
    unredeemed_prizes.exists?
  end

  # The prize this gate can still redeem for `shop_item`, if any. Drives both
  # the free-price gate in the shop and Mission::PrizeRedemption.record!.
  def redeemable_prize_for(shop_item)
    unredeemed_prizes.find_by(shop_item_id: shop_item.id)
  end
end
