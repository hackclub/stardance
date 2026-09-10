require "test_helper"

# The clickable month calendar beside the manual date field in the credit
# modal. Picking a day only fills that field, so this route stays read-only.
class Admin::Users::StreakCalendarsControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  # Mid-August, so the calendar has a month either side of it to page to.
  FROZEN_NOW = Time.utc(2026, 8, 18, 12, 0, 0)

  setup do
    travel_to FROZEN_NOW
    @helper = create_user(slack_id: "U_CAL_HELPER", display_name: "cal_helper")
    @helper.grant_role!(:helper)
    @member = create_user(slack_id: "U_CAL_MEMBER", display_name: "cal_member")
    @today = @member.streak_today_date
  end

  test "a day the person has already lived through is pickable and carries its date" do
    kept = @today - 2
    StreakActivity.create!(user: @member, activity_date: kept,
                           coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    sign_in @helper

    get admin_user_streak_calendar_path(@member, year: kept.year, month: kept.month)

    assert_response :success
    assert_select ".streak-calendar__month", "August 2026"
    assert_select "button.streak-calendar__cell--pickable[data-streak-day-picker-date-param=?]", kept.to_s
  end

  test "a day that has not happened yet cannot be picked" do
    tomorrow = @today + 1
    sign_in @helper

    get admin_user_streak_calendar_path(@member, year: tomorrow.year, month: tomorrow.month)

    assert_response :success
    assert_select "[data-streak-day-picker-date-param=?]", tomorrow.to_s, count: 0
  end

  test "the calendar clamps to the months the program actually ran" do
    sign_in @helper

    get admin_user_streak_calendar_path(@member, year: 2020, month: 1)

    assert_response :success
    assert_select ".streak-calendar__month", StreakActivity::CALENDAR_FIRST_MONTH.strftime("%B %Y")
    assert_select "span.streak-calendar__nav-btn--disabled", text: "‹"
  end

  test "the month either side of the run is a plain link, so paging needs no javascript" do
    sign_in @helper

    get admin_user_streak_calendar_path(@member, year: @today.year, month: @today.month)

    assert_response :success
    assert_select "a.streak-calendar__nav-btn[href=?]",
                  admin_user_streak_calendar_path(@member, year: 2026, month: 7)
    assert_select "a.streak-calendar__nav-btn[href=?]",
                  admin_user_streak_calendar_path(@member, year: 2026, month: 9)
  end

  test "a sticker day keeps its art without nesting a button inside the day button" do
    Flipper.enable(:sticky_streaks)
    StickyStreak.create!(user: @member, started_on: @today)
    StreakActivity.create!(user: @member, activity_date: @today,
                           coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    StickyStreakReward.create!(day_number: 1, shop_item: sticker)
    sign_in @helper

    get admin_user_streak_calendar_path(@member, year: @today.year, month: @today.month)

    assert_response :success
    assert_select ".streak-calendar__cell--pickable .streak-mark__sticker"
    assert_select ".streak-calendar__cell--pickable button", count: 0
    assert_select "[data-action='sticker-zoom#open']", count: 0
  ensure
    Flipper.disable(:sticky_streaks)
  end

  test "the credit modal renders the calendar wired to the date field" do
    sign_in @helper

    get admin_user_path(@member)

    assert_response :success
    assert_select "form[data-controller='streak-day-picker'] [data-streak-day-picker-target='date']"
    assert_select "form[data-controller='streak-day-picker'] turbo-frame#admin_user_streak_calendar"
  end

  test "a member with no admin role never reaches the route" do
    sign_in create_user(slack_id: "U_CAL_NOBODY", display_name: "cal_nobody")

    get admin_user_streak_calendar_path(@member)

    assert_response :not_found
  end

  test "an admin role without support duties is refused" do
    shop_manager = create_user(slack_id: "U_CAL_SHOP", display_name: "cal_shop")
    shop_manager.grant_role!(:shop_manager)
    sign_in shop_manager

    get admin_user_streak_calendar_path(@member)

    assert_response :forbidden
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
