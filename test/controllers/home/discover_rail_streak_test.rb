require "test_helper"

# The streak rail widget is where the Sticky Streak lives: the intro notice, the
# 21-day board and the claim signal all render from here.
class Home::DiscoverRailStreakTest < ActionDispatch::IntegrationTest
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    Flipper.enable(:sticky_streaks)
    @user = create_user(slack_id: "U-rail-sticky", display_name: "railsticky", verified: true)
    @user.update!(onboarded_at: Time.current, has_gotten_free_stickers: true)
    @user.identities.create!(provider: "hackatime", uid: "ht-rail", access_token: "fake")
    project = @user.projects.create!(title: "Orbit", description: "a test project")
    @user.hackatime_projects.create!(name: "orbit", project_id: project.id)
    sign_in @user
  end

  teardown { Flipper.disable(:sticky_streaks) }

  test "the start control shows before the challenge is started" do
    get streak_home_discover_rail_path

    assert_response :success
    assert_select ".sticky-start__summary", "Sticky Streak"
  end

  test "a started challenge swaps stars for stickers and offers the claim" do
    today = @user.streak_today_date
    streak = StickyStreak.create!(user: @user, started_on: today - 1)
    [ streak.started_on, today ].each do |date|
      StreakActivity.create!(user: @user, activity_date: date,
                             coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    end
    StickyStreakReward.create!(day_number: 1, shop_item: sticker)

    get streak_home_discover_rail_path

    assert_response :success
    assert_select "a[href=?] .sticky-claim__day",
                  shop_item_path(StickyStreakReward.find_by(day_number: 1).shop_item, sticky_streak_day: 1),
                  "Claim day 1"
    assert_select ".streak-widget__toggle-badge", text: /1 sticker to claim/

    # Day 1 has a sticker and was completed, day 2 has none yet, and the rest of
    # the week is outside the run.
    assert_select ".streak-widget__week .streak-mark__sticker--claimable"
    assert_select ".streak-widget__week .streak-mark--unknown", minimum: 1
    assert_select ".streak-widget__week .streak-mark--today", 1
    assert_select ".streak-widget__cal-grid .streak-mark--today", 1
    assert_select ".streak-widget__week .streak-mark__star", minimum: 1
    assert_select ".streak-widget__cal-grid .streak-mark__sticker--claimable"
  end

  test "the calendar keeps its plain stars while the challenge is switched off" do
    Flipper.disable(:sticky_streaks)
    today = @user.streak_today_date
    StickyStreak.create!(user: @user, started_on: today)
    StreakActivity.create!(user: @user, activity_date: today,
                           coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    StickyStreakReward.create!(day_number: 1, shop_item: sticker)

    get streak_home_discover_rail_path

    assert_response :success
    assert_select ".streak-mark__sticker", count: 0
    assert_select ".sticky-claim", count: 0
    assert_select ".sticky-start__summary", count: 0
    assert_select ".streak-widget__week .streak-mark__star", minimum: 1
  end

  test "clicking a sticker opens the shared zoom dialog" do
    today = @user.streak_today_date
    StickyStreak.create!(user: @user, started_on: today)
    StreakActivity.create!(user: @user, activity_date: today,
                           coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    item = sticker
    StickyStreakReward.create!(day_number: 1, shop_item: item)

    get streak_home_discover_rail_path

    assert_response :success
    assert_select "dialog.sticker-zoom", 1
    assert_select ".streak-widget__week [data-action='sticker-zoom#open'][data-sticker-zoom-name-param=?]",
                  item.name
    assert_select "[data-sticker-zoom-claim-href-param=?]", shop_item_path(item, sticky_streak_day: 1)
    assert_select "[data-sticker-zoom-description-param=?]", item.description
    assert_select "dialog.sticker-zoom [data-sticker-zoom-target='description']", 1
  end

  test "the week view names sticky days in the tooltip" do
    today = @user.streak_today_date
    streak = StickyStreak.create!(user: @user, started_on: today - 1)
    [ streak.started_on, today ].each do |date|
      StreakActivity.create!(user: @user, activity_date: date,
                             coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    end
    StickyStreakReward.create!(day_number: 2, shop_item: sticker)

    get streak_home_discover_rail_path

    assert_response :success
    assert_select ".streak-widget__week [data-tooltip-message-value=?]",
                  "5 minutes · Sticky Streak day 1"
    assert_select ".streak-widget__week [data-tooltip-message-value=?]",
                  "5 minutes · Sticky Streak day 2 (ready to claim)"
  end

  test "a sticky day with no coding time still gets a tooltip" do
    today = @user.streak_today_date
    StickyStreak.create!(user: @user, started_on: today)

    get streak_home_discover_rail_path

    assert_response :success
    assert_select ".streak-widget__week [data-tooltip-message-value=?]", "Sticky Streak day 1"
  end

  test "the month nav can page forward to the last calendar month" do
    get streak_home_discover_rail_path

    assert_response :success
    assert_select "[data-action='streak#nextMonth']"
  end

  private

  def sticker
    item = ShopItem.new(name: "Orbit Sticker", description: "sticker", ticket_cost: 5,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true)
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end
end
