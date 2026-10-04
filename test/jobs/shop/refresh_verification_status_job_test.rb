require "test_helper"

class Shop::RefreshVerificationStatusJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(
      slack_id: "U_REFRESH_SHOP_#{SecureRandom.hex(6)}",
      email: "refresh-shop-#{SecureRandom.hex(4)}@example.com",
      display_name: "Refresh Shop User",
      verification_status: "verified",
      ysws_eligible: true
    )
    @user.identities.create!(
      provider: "hack_club",
      uid: "hc_#{SecureRandom.hex(6)}",
      access_token: "token_#{SecureRandom.hex(8)}"
    )
    @order = create_awaiting_verification_order(@user)
  end

  test "ignores non-fatal ineligible payloads" do
    payload = { "verification_status" => "ineligible", "ysws_eligible" => false, "fatal_rejection" => false }

    HCAService.stub(:identity!, payload) do
      Shop::RefreshVerificationStatusJob.perform_now
    end

    assert @order.reload.awaiting_verification?
    assert @user.reload.verification_verified?
    assert_not @user.banned?
  end

  test "rejects and bans on fatal ineligible payloads" do
    payload = { "verification_status" => "ineligible", "ysws_eligible" => false, "fatal_rejection" => true }

    HCAService.stub(:identity!, payload) do
      Shop::RefreshVerificationStatusJob.perform_now
    end

    assert @order.reload.rejected?
    assert @user.reload.verification_ineligible?
    assert @user.banned?
  end

  private

  def create_awaiting_verification_order(user)
    item = ShopItem.create!(
      name: "Test Item #{SecureRandom.hex(4)}",
      ticket_cost: 0,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )

    order = user.shop_orders.new(
      shop_item: item,
      quantity: 1,
      frozen_item_price: 0,
      frozen_address: { "country" => "US" },
      aasm_state: "awaiting_verification"
    )
    order.save!(validate: false)
    order
  end
end
