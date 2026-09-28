require "test_helper"

# Sticky Streak days are redeemed through the normal shop item page, so the
# claimer picks an address and checks out like any other order.
class Shop::StickyStreakRedemptionTest < ActionDispatch::IntegrationTest
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze
  ADDRESS = { "id" => "addr-1", "country" => "US", "primary" => true }.freeze
  IDENTITY = { "addresses" => [ ADDRESS ], "phone_number" => "+15551234567" }.freeze

  setup do
    @user = create_user(slack_id: "U-shop-sticky", display_name: "shopsticky", verified: true)
    @user.update!(has_gotten_free_stickers: true)
    @item = build_item("Day One Sticker")

    @streak = StickyStreak.create!(user: @user, started_on: @user.streak_today_date)
    StreakActivity.create!(user: @user, activity_date: @streak.started_on,
                           coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    StickyStreakReward.create!(day_number: 1, shop_item: @item)

    sign_in @user
  end

  test "the item page prices the day's sticker at nothing and carries the gate" do
    with_address do
      get shop_item_path(@item, sticky_streak_day: 1)
    end

    assert_response :success
    assert_select "[data-order-form-free-value='true']"
    assert_select "input[name='sticky_streak_day'][value='1']"
  end

  test "checking out places a free order and closes the day" do
    with_address do
      post shop_orders_path, params: { shop_item_id: @item.id, quantity: 1, sticky_streak_day: 1 }
    end

    claim = StickyStreakClaim.sole
    assert_equal 1, claim.day_number
    assert_equal @item, claim.shop_order.shop_item
    assert_equal 0, claim.shop_order.frozen_item_price
    assert_equal ADDRESS["id"], claim.shop_order.frozen_address["id"]
    assert_not @streak.reload.claimable_day?(1)
  end

  test "a day that was not earned is not a valid gate" do
    StreakActivity.find_by(user: @user).update!(coded_seconds: 0)

    with_address do
      post shop_orders_path, params: { shop_item_id: @item.id, quantity: 1, sticky_streak_day: 1 }
    end

    assert_equal 0, StickyStreakClaim.count
  end

  test "a claimed day cannot be redeemed twice" do
    with_address do
      post shop_orders_path, params: { shop_item_id: @item.id, quantity: 1, sticky_streak_day: 1 }
      post shop_orders_path, params: { shop_item_id: @item.id, quantity: 1, sticky_streak_day: 1 }
    end

    assert_equal 1, StickyStreakClaim.count
  end

  test "the gate does not unlock a sticker from a different day" do
    other = build_item("Day Two Sticker")
    StickyStreakReward.create!(day_number: 2, shop_item: other)

    with_address do
      post shop_orders_path, params: { shop_item_id: other.id, quantity: 1, sticky_streak_day: 1 }
    end

    assert_equal 0, StickyStreakClaim.count
  end

  test "the gate waives the earn-it-first checks the item would otherwise impose" do
    gated = build_item("Starling Plushie", requires_achievement: %w[super_star])
    StickyStreakReward.find_by(day_number: 1).update!(shop_item: gated)

    with_address do
      post shop_orders_path, params: { shop_item_id: gated.id, quantity: 1, sticky_streak_day: 1 }
    end

    assert_equal gated, StickyStreakClaim.sole.shop_order.shop_item
  end

  test "a disabled item stays unclaimable, gate or no gate" do
    retired = build_item("Retired Sticker")
    StickyStreakReward.find_by(day_number: 1).update!(shop_item: retired)
    retired.update!(enabled: false)

    with_address do
      post shop_orders_path, params: { shop_item_id: retired.id, quantity: 1, sticky_streak_day: 1 }
    end

    assert_equal 0, StickyStreakClaim.count
  end

  test "the same item still refuses an ordinary purchase" do
    gated = build_item("Starling Plushie", requires_achievement: %w[super_star])
    order = @user.shop_orders.new(shop_item: gated, quantity: 1, frozen_address: ADDRESS)

    assert_not order.valid?
    assert_match(/achievement/, order.errors.full_messages.to_sentence)
  end

  test "stock is a physical limit, so the gate does not waive it" do
    sold_out = build_item("Sold Out Sticker", limited: true, stock: 0)
    StickyStreakReward.find_by(day_number: 1).update!(shop_item: sold_out)

    with_address do
      post shop_orders_path, params: { shop_item_id: sold_out.id, quantity: 1, sticky_streak_day: 1 }
    end

    assert_equal 0, StickyStreakClaim.count
  end

  private

  # User#addresses reads the HCA identity payload, so stubbing the service
  # covers whichever User instance the controller is holding.
  def with_address(&block) = HCAService.stub(:identity, IDENTITY, &block)

  def build_item(name, **attributes)
    item = ShopItem.new({ name: name, description: "sticker", ticket_cost: 25,
                          type: "ShopItem::ThirdPartyPhysical", enabled: true }.merge(attributes))
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
