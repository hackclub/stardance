require "test_helper"

# == Schema Information
#
# Table name: sticky_streaks
#
#  id         :bigint           not null, primary key
#  started_on :date             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_sticky_streaks_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class StickyStreakTest < ActiveSupport::TestCase
  PIXEL_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")

  setup do
    @user = create_user(slack_id: "U-sticky", display_name: "sticky", verified: true)
    @user.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate on ShopOrder
    @today = @user.streak_today_date
    @streak = StickyStreak.create!(user: @user, started_on: @today - 4)
    @item = build_item("Comet Sticker")
  end

  test "days the user hit the goal on count as completed" do
    complete_days(1, 2, 3)

    assert_equal [ 1, 2, 3 ].to_set, @streak.completed_days
    assert_equal 4, @streak.settled_days
    assert_equal 5, @streak.current_day
  end

  test "a settled day below the goal breaks the run" do
    complete_days(1, 2)
    log_seconds(3, StreakActivity::DAILY_GOAL_SECONDS - 1)
    complete_days(4)

    assert @streak.failed?
    assert_equal 3, @streak.missed_day
  end

  test "today is not settled yet so an empty today does not break the run" do
    complete_days(1, 2, 3, 4)

    assert_not @streak.failed?
    assert @streak.active?
  end

  test "crediting a missed day repairs a broken run" do
    complete_days(1, 2, 4)
    StickyStreakReward.create!(day_number: 4, shop_item: @item)

    assert_predicate @streak, :failed?
    assert_equal 3, @streak.missed_day

    StreakActivity.credit!(
      user: @user, date: @streak.date_for(3),
      granted_by: create_user(slack_id: "U-sticky-helper", display_name: "stickyhelper"),
      reason: "Hackatime lost the day"
    )

    repaired = StickyStreak.find(@streak.id)
    assert_not_predicate repaired, :failed?
    assert_nil repaired.missed_day
    assert_includes repaired.completed_days, 3
    assert repaired.claimable_day?(4), "the day after the repaired one is claimable again"
  end

  test "a day is claimable once completed and a reward is configured" do
    complete_days(1, 2)
    StickyStreakReward.create!(day_number: 2, shop_item: @item)

    assert_not @streak.claimable_day?(1), "day without a reward is not claimable"
    assert @streak.claimable_day?(2)
    assert_equal 2, @streak.latest_claimable_day
  end

  test "days from the miss onwards are never claimable" do
    complete_days(1, 3)
    log_seconds(2, 0)
    (1..3).each { |day| StickyStreakReward.create!(day_number: day, shop_item: @item) }

    assert @streak.claimable_day?(1)
    assert_not @streak.claimable_day?(2)
    assert_not @streak.claimable_day?(3), "a completed day after the miss stays locked"
    assert_equal [ 1 ], @streak.claimable_days
  end

  test "recording a claim closes the day" do
    complete_days(1)
    StickyStreakReward.create!(day_number: 1, shop_item: @item)

    claim = @streak.record_claim!(shop_order: free_order, day: 1)

    assert_equal 1, claim.day_number
    assert_equal @item, claim.shop_order.shop_item
    assert_equal 0, claim.shop_order.frozen_item_price
    assert_not StickyStreak.find(@streak.id).claimable_day?(1)
  end

  test "recording a claim for a day the user did not code is refused" do
    log_seconds(1, 0)
    StickyStreakReward.create!(day_number: 1, shop_item: @item)

    assert_raises(StickyStreak::NotClaimable) { @streak.record_claim!(shop_order: free_order, day: 1) }
  end

  test "a user only ever gets one run" do
    duplicate = StickyStreak.new(user: @user, started_on: @today)

    assert_not duplicate.valid?
  end

  test "day_stats splits each day into banked, live and still ahead" do
    complete_days(1, 2, 3, 4)

    # A second run that broke on its day 2, so it only ever banked day 1.
    breaker = create_user(slack_id: "U-sticky-broke", display_name: "stickybroke")
    broken = StickyStreak.create!(user: breaker, started_on: breaker.streak_today_date - 3)
    StreakActivity.create!(user: breaker, activity_date: broken.date_for(1),
                           coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    StreakActivity.create!(user: breaker, activity_date: broken.date_for(3),
                           coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)

    stats = StickyStreak.day_stats.index_by(&:day)

    # @streak banked days 1..4 and is living day 5; the broken run banked day 1 only.
    assert_equal [ 2, 0, 0 ], counts(stats[1])
    assert_equal [ 1, 0, 0 ], counts(stats[2])
    assert_equal [ 1, 0, 0 ], counts(stats[4])
    assert_equal [ 0, 1, 0 ], counts(stats[5])
    assert_equal [ 0, 0, 1 ], counts(stats[6])
    assert_equal [ 0, 0, 1 ], counts(stats[StickyStreak::LENGTH])
  end

  test "day_stats reports every day as empty when nobody has started" do
    @streak.destroy!

    stats = StickyStreak.day_stats

    assert_equal StickyStreak::LENGTH, stats.size
    assert stats.all? { |stat| stat.total.zero? }
  end

  private

  def counts(stat) = [ stat.successful, stat.in_progress, stat.potential ]

  def complete_days(*days)
    days.each { |day| log_seconds(day, StreakActivity::DAILY_GOAL_SECONDS) }
  end

  def log_seconds(day, seconds)
    StreakActivity.create!(user: @user, activity_date: @streak.date_for(day), coded_seconds: seconds)
  end

  # Stands in for the order the shop places once the gate is accepted.
  def free_order
    order = @user.shop_orders.new(shop_item: @item, quantity: 1, aasm_state: "pending",
                                  frozen_address: { "id" => "addr-1", "country" => "US" })
    order.redeeming_sticky_streak = @streak
    order.save!
    order
  end

  def build_item(name)
    item = ShopItem.new(name: name, description: "sticker", ticket_cost: 5,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true)
    item.image.attach(io: StringIO.new(PIXEL_PNG), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
