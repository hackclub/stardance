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
require "test_helper"

class ShopCardGrantTest < ActiveSupport::TestCase
  test "only a status HCB actually reported closes a grant" do
    ShopCardGrant::CLOSED_STATUSES.each do |status|
      assert ShopCardGrant.closed_grant?({ "status" => status }), "#{status} is terminal"
    end

    assert_not ShopCardGrant.closed_grant?({ "status" => "active" })
  end

  # Blank is "we couldn't read it", not "it's still live". Callers that spend
  # money have to raise on an unreadable status rather than let this answer for
  # them - see Shop::HCBGrantFulfillable.
  test "an empty payload never closes a grant" do
    assert_not ShopCardGrant.closed_grant?(nil)
    assert_not ShopCardGrant.closed_grant?({})
  end
end
