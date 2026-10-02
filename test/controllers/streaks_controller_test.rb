require "test_helper"

class StreaksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(slack_id: "U-streak-month", display_name: "streakmonth")
    sign_in @user
  end

  # Bounds come from the constants so moving the program window does not rot
  # these; the last month shifted once already when the end date became October.
  LAST_MONTH = StreakActivity::CALENDAR_LAST_MONTH
  FIRST_MONTH = StreakActivity::CALENDAR_FIRST_MONTH

  test "the calendar pages forward to the last program month even before it starts" do
    before_last = LAST_MONTH - 1.month

    get streak_month_path(year: before_last.year, month: before_last.month)

    assert_response :success
    assert_select "[data-action='streak#nextMonth']"
  end

  test "the last program month has no next arrow" do
    get streak_month_path(year: LAST_MONTH.year, month: LAST_MONTH.month)

    assert_response :success
    assert_select ".streak-calendar__month", LAST_MONTH.strftime("%B %Y")
    assert_select "[data-action='streak#nextMonth']", count: 0
  end

  test "the first program month has no previous arrow" do
    get streak_month_path(year: FIRST_MONTH.year, month: FIRST_MONTH.month)

    assert_response :success
    assert_select "[data-action='streak#prevMonth']", count: 0
  end
end
