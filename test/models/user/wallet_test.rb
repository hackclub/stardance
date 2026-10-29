require "test_helper"
require "base64"

class User::WalletTest < ActiveSupport::TestCase
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @user = create_user(slack_id: "U_WALLET", display_name: "wallet_user")
    @user.ledger_entries.create!(ledgerable: @user, amount: 100, reason: "Grant", created_by: "test")

    item = ShopItem.new(name: "Wallet item", description: "d", ticket_cost: 50,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true)
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    order = ShopOrder.new(user: @user, shop_item: item, quantity: 1, frozen_item_price: 50,
                          frozen_address: { "country" => "US" })
    order.save!(validate: false) # charges the 50 through ShopOrder's own ledger entry
    @user.ledger_entries.create!(ledgerable: order, amount: 50, reason: "Refund", created_by: "System")
  end

  test "a shop refund doesn't count as stardust earned" do
    assert_equal 100, @user.balance
    assert_equal 100, @user.total_earned
    assert_equal 100, @user.reload.approx_total_earned
  end

  test "the nightly refresh leaves shop refunds out of total earned" do
    @user.update_columns(approx_total_earned: 0)

    RefreshApproxBalancesJob.perform_now

    assert_equal 100, @user.reload.approx_total_earned
    assert_equal 100, @user.approx_balance
  end
end
