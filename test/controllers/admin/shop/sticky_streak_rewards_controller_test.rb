require "test_helper"

class Admin::Shop::StickyStreakRewardsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @admin = create_user(slack_id: "U_SSR_ADMIN", display_name: "ssr_admin")
    @admin.grant_role!(:admin)
    sign_in @admin

    @item = ShopItem.new(name: "Day One Sticker", description: "sticker", ticket_cost: 5,
                         type: "ShopItem::ThirdPartyPhysical", enabled: true)
    @item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    @item.save!
  end

  test "the editor lists every challenge day" do
    get admin_shop_sticky_streak_rewards_path

    assert_response :success
    assert_select "select[name='days[1]']"
    assert_select "select[name='days[#{StickyStreak::LENGTH}]']"
  end

  test "saving sets and clears rewards" do
    patch admin_shop_sticky_streak_rewards_path, params: { days: { "1" => @item.id.to_s } }
    assert_equal @item, StickyStreakReward.find_by(day_number: 1).shop_item

    patch admin_shop_sticky_streak_rewards_path, params: { days: { "1" => "" } }
    assert_nil StickyStreakReward.find_by(day_number: 1)
  end

  test "the day overview charts every day once a run exists" do
    runner = create_user(slack_id: "U_SSR_RUN", display_name: "ssr_run")
    streak = StickyStreak.create!(user: runner, started_on: runner.streak_today_date - 1)
    StreakActivity.create!(user: runner, activity_date: streak.started_on,
                           coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)

    get admin_shop_sticky_streak_rewards_path

    assert_response :success
    assert_select ".sticky-funnel__row", count: StickyStreak::LENGTH
    assert_select ".sticky-funnel__row:first-of-type .sticky-funnel__bar--successful"
    assert_select ".sticky-funnel__row:nth-of-type(2) .sticky-funnel__bar--in-progress"
    assert_select ".sticky-funnel__row:last-of-type .sticky-funnel__bar--potential"
    assert_select ".sticky-funnel__row:first-of-type .sticky-funnel__track[data-tooltip-message-value=?]",
                  "1 successful · 0 in progress · 0 potential"
    assert_select ".sticky-funnel__counts", count: 0
  end

  test "the day overview says so when nobody has started" do
    get admin_shop_sticky_streak_rewards_path

    assert_response :success
    assert_select ".sticky-funnel__row", count: 0
    assert_select "p", text: /Nobody has started a Sticky Streak yet/
  end

  test "non-admins are turned away" do
    sign_in create_user(slack_id: "U_SSR_PLAIN", display_name: "ssr_plain")

    get admin_shop_sticky_streak_rewards_path

    assert_response :not_found
  end
end
