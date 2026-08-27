require "test_helper"

class StreaksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(slack_id: "U-streak-month", display_name: "streakmonth")
    sign_in @user
  end

  test "the calendar pages forward to the last program month even before it starts" do
    get streak_month_path(year: 2026, month: 8)

    assert_response :success
    assert_select "[data-action='streak#nextMonth']"
  end

  test "the last program month has no next arrow" do
    get streak_month_path(year: 2026, month: 9)

    assert_response :success
    assert_select ".streak-widget__cal-month", "September 2026"
    assert_select "[data-action='streak#nextMonth']", count: 0
  end

  test "the first program month has no previous arrow" do
    get streak_month_path(year: 2026, month: 6)

    assert_response :success
    assert_select "[data-action='streak#prevMonth']", count: 0
  end
end
