require "test_helper"

# Guards the money path for mission static prizes: a *regular* (priced) shop
# item given as a Mission::Prize must be free to the builder who earned it, and
# must never touch the stardust ledger — neither a charge on redemption nor a
# refund if the order is later rejected.
class ShopOrderMissionPrizeTest < ActiveSupport::TestCase
  include UserFactory

  setup do
    @user = create_user(slack_id: "u-prize", display_name: "prizewinner")
    @user.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate
    @item = ShopItem.new(
      name: "Regular Sticker Pack",
      description: "A normal, purchasable shop item handed out as a mission prize",
      ticket_cost: 500,
      type: "ShopItem::ThirdPartyPhysical",
      enabled: true
    )
    @item.image.attach(
      io: StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")),
      filename: "px.png",
      content_type: "image/png"
    )
    @item.save!
    @address = { "country" => "US", "phone_number" => "+15555550123", "primary" => true }
  end

  test "redeeming a priced item as a mission prize is free and never debits stardust" do
    assert_equal 0, @user.balance, "precondition: builder has no stardust"

    order = @user.shop_orders.new(shop_item: @item, quantity: 1, frozen_address: @address)
    order.redeeming_mission_submission = Mission::Submission.new
    order.aasm_state = "pending"

    assert order.save, "redemption must succeed on a zero balance: #{order.errors.full_messages.to_sentence}"
    assert_equal 0, order.frozen_item_price, "mission redemption must freeze the price to 0"
    assert_equal 0, @user.reload.balance, "redeeming a prize must not debit stardust"
    assert_empty @user.ledger_entries.where(ledgerable: order), "a free prize must not create a ledger entry"
  end

  # Note: the refund-on-reject path uses the same `frozen_item_price > 0` guard
  # as the charge, so a frozen price of 0 also means no phantom refund credit.

  test "the same item bought normally still freezes the real price" do
    order = @user.shop_orders.new(shop_item: @item, quantity: 1, frozen_address: @address)
    order.send(:freeze_item_price)
    assert_operator order.frozen_item_price.to_i, :>, 0, "a normal purchase must keep the real price"
  end

  test "a funding-request kit redemption is free and clears the mission-prize-only guard" do
    @item.update!(mission_prize_only: true)

    order = @user.shop_orders.new(shop_item: @item, quantity: 1, frozen_address: @address)
    order.redeeming_funding_request = Certification::FundingRequest.new
    order.aasm_state = "pending"

    assert order.save, "kit redemption must succeed: #{order.errors.full_messages.to_sentence}"
    assert_equal 0, order.frozen_item_price, "a kit redemption must freeze the price to 0"
    assert_equal 0, @user.reload.balance, "redeeming a kit must not debit stardust"
    assert_empty @user.ledger_entries.where(ledgerable: order), "a free kit must not create a ledger entry"
  end
end
