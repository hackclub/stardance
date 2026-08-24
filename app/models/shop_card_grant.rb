# == Schema Information
#
# Table name: shop_card_grants
#
#  id                    :bigint           not null, primary key
#  expected_amount_cents :integer
#  hcb_grant_hashid      :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  shop_item_id          :bigint           not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_shop_card_grants_on_shop_item_id  (shop_item_id)
#  index_shop_card_grants_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (shop_item_id => shop_items.id)
#  fk_rails_...  (user_id => users.id)
#
class ShopCardGrant < ApplicationRecord
  belongs_to :user
  belongs_to :shop_item

  class << self
    # Reads an HCB card-grant payload (the body HCBService.show_card_grant
    # returns) the same way everywhere a grant's safety is judged - shop
    # fulfillment (Shop::HCBGrantFulfillable#topupable?) and hardware review undo
    # (Certification::ReviewUndoer) - so the field handling lives in one place.
    def canceled_grant?(hcb_data)
      hcb_data.present? && hcb_data["status"].to_s == "canceled"
    end

    # A grant whose remaining balance still equals the amount granted is
    # untouched; any less has been spent. Missing/unreadable data is treated as
    # spent (unsafe) rather than assumed clean - this guards real money.
    # `expected_cents` is the amount we believe was granted, used only when the
    # payload omits amount_cents.
    def spent_grant?(hcb_data, expected_cents: nil)
      return true if hcb_data.blank?

      balance = hcb_data["balance_cents"]
      return true if balance.nil?

      balance.to_i < (hcb_data["amount_cents"] || expected_cents).to_i
    end
  end

  def hcb_data
    @hcb_data ||= HCBService.show_card_grant(hashid: hcb_grant_hashid)
  end

  # True when HCB reports this grant already cancelled.
  def canceled?
    self.class.canceled_grant?(hcb_data)
  end

  def hcb_url
    "#{HCBService.base_url}/grants/#{stripped_hashid}"
  end

  def topup_url
    "#{HCBService.base_url}/donations/start/#{HCBService.slug}?email=#{user.grant_email}&message=Top up for #{HCBService.base_url}/grants/#{stripped_hashid}&name=#{user.full_name}&goods=true"
  end

  def topup!(amount_cents)
    HCBService.topup_card_grant(
      hashid: hcb_grant_hashid,
      amount_cents: amount_cents
    )
    self.expected_amount_cents += amount_cents
    save!
  end

  private

  def stripped_hashid
    hcb_grant_hashid[4..]
  end
end
