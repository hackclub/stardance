require "test_helper"

class DailyRollsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    Flipper.enable(:week_2_release)
  end

  test "the page and rolling 404 when the week_2_release flag is off" do
    Flipper.disable(:week_2_release)
    sign_in @user

    get rng_path
    assert_response :not_found

    get rng_history_path
    assert_response :not_found

    assert_no_difference "DailyRoll.count" do
      post daily_roll_path, as: :turbo_stream
    end
    assert_response :not_found
  end

  test "logged-out rolling stores a cookie and shows the sign-up CTA, not a DB roll" do
    assert_no_difference "DailyRoll.count" do
      post daily_roll_path, as: :turbo_stream
    end

    assert_response :success
    assert_match "rng-hero", response.body
    assert_match "create an account to save this roll", response.body
    assert_match "rng-hero__signup", response.body
  end

  test "a logged-out roll is claimed onto the account on sign in" do
    # Roll while logged out — goes to a cookie, not the DB.
    assert_no_difference "DailyRoll.count" do
      post daily_roll_path, as: :turbo_stream
    end

    # Signing in saves that pending roll to the account.
    assert_difference "DailyRoll.count", 1 do
      sign_in @user
    end

    roll = DailyRoll.for_today(@user)
    assert roll.present?
    assert_includes 0..DailyRoll::MAX_VALUE, roll.value
  end

  test "logged-out leaderboard offers a roll but no history" do
    get rng_path

    assert_response :success
    assert_select "form[action=?] [type=submit]", daily_roll_path
    assert_no_match(/see history/, response.body)
  end

  test "rolling creates today's roll and streams the widget back" do
    sign_in @user

    assert_difference "DailyRoll.count", 1 do
      post daily_roll_path, as: :turbo_stream
    end

    assert_response :success
    assert_match "daily-roll-widget", response.body
    assert_match "copy to share", response.body
    assert DailyRoll.for_today(@user).present?
  end

  test "rolling ignores any submitted value or date — the server generates them" do
    sign_in @user

    # Submit an out-of-range value and a past date; both must be ignored.
    post daily_roll_path,
         params: { daily_roll: { value: 9_999_999_999, rolled_on: 1.year.ago.to_date.iso8601 } },
         as: :turbo_stream

    assert_response :success
    roll = DailyRoll.for_today(@user)
    assert roll.present?, "the server should generate a roll, ignoring the request body"
    assert_includes 0..DailyRoll::MAX_VALUE, roll.value, "submitted value must not be used"
    assert_equal Date.current, roll.rolled_on, "submitted date must not be used"
  end

  test "rolling twice in a day keeps the first roll" do
    sign_in @user
    first = DailyRoll.roll!(@user)

    assert_no_difference "DailyRoll.count" do
      post daily_roll_path, as: :turbo_stream
    end

    assert_response :success
    assert_equal first, DailyRoll.for_today(@user)
  end

  test "leaderboard page is public and lists today's rolls" do
    DailyRoll.create!(user: users(:two), value: 1_234_567, rolled_on: Date.current)
    DailyRoll.create!(user: users(:three), value: 42, rolled_on: Date.current)

    get rng_path

    assert_response :success
    assert_match "1,234,567", response.body
    assert_match "42", response.body
    assert_match users(:two).display_name, response.body
  end

  test "leaderboard page shows the all-time best when it isn't today's leader" do
    DailyRoll.create!(user: users(:three), value: 999_999, rolled_on: 3.days.ago.to_date)
    DailyRoll.create!(user: users(:one), value: 5, rolled_on: Date.current)

    get rng_path

    assert_response :success
    assert_match "All-time best", response.body
    assert_match "999,999", response.body
  end

  test "leaderboard page offers a roll button when you haven't rolled" do
    sign_in @user

    get rng_path

    assert_response :success
    assert_match "rolled today", response.body
    assert_select "form[action=?] [type=submit]", daily_roll_path
  end

  test "dev clear removes today's roll so you can re-roll" do
    sign_in @user
    DailyRoll.roll!(@user)

    delete clear_daily_roll_path

    assert_response :redirect
    assert_nil DailyRoll.for_today(@user)
  end

  test "leaderboard page browses past days via the date param" do
    DailyRoll.create!(user: users(:two), value: 123_456, rolled_on: Date.current)
    DailyRoll.create!(user: users(:three), value: 987_654, rolled_on: Date.yesterday)

    get rng_path(date: Date.yesterday.iso8601)

    assert_response :success
    assert_match "987,654", response.body
    assert_no_match(/123,456/, response.body)
    assert_match "Yesterday", response.body
    assert_select "a[href=?]", rng_path, text: "›"
  end

  test "leaderboard paginates a busy day and clamps the page param" do
    rolls = Array.new(DailyRollsController::PAGE_SIZE + 5) do |i|
      user = User.create!(email: "pager#{i}@example.test", display_name: "pager_#{i}")
      DailyRoll.create!(user: user, value: 1_000 - i, rolled_on: Date.current)
    end

    # Page 1 shows the first page worth, not all of them.
    get rng_path
    assert_response :success
    assert_match "Page 1 of 2", response.body
    assert_match rolls.first.user.display_name, response.body
    assert_no_match(/#{rolls.last.user.display_name}/, response.body)

    # Page 2 shows the overflow with continued ranks, no podium.
    get rng_path(page: 2)
    assert_response :success
    assert_match rolls.last.user.display_name, response.body
    assert_match "#51", response.body

    # Out-of-range pages clamp into [1, total_pages].
    get rng_path(page: 999)
    assert_response :success
    assert_match "Page 2 of 2", response.body

    get rng_path(page: 0)
    assert_response :success
    assert_match "Page 1 of 2", response.body
  end

  test "leaderboard page clamps invalid and future dates to today" do
    DailyRoll.create!(user: users(:two), value: 7, rolled_on: Date.current)

    get rng_path(date: "not-a-date")
    assert_response :success

    get rng_path(date: (Date.current + 30).iso8601)
    assert_response :success
    assert_match "Today", response.body
  end

  test "leaderboard hero shows your number with copy-to-share and history link" do
    sign_in @user
    DailyRoll.create!(user: @user, value: 12_345, rolled_on: Date.current)

    get rng_path

    assert_response :success
    assert_match "Your number today", response.body
    assert_match "data-copy-text-value=\"stardance rng day ", response.body
    assert_match "🎲 12,345 · ranked #1 so far", response.body
    assert_select "a[href=?]", rng_history_path
  end

  test "browsing a past date shows your roll for that day without copy to share" do
    sign_in @user
    DailyRoll.create!(user: @user, value: 777, rolled_on: Date.yesterday)
    DailyRoll.create!(user: @user, value: 5, rolled_on: Date.current)

    get rng_path(date: Date.yesterday.iso8601)

    assert_response :success
    assert_match "Your number ·", response.body
    assert_match "777", response.body
    assert_match "#1 that day", response.body
    assert_no_match(/copy to share/, response.body)
  end

  test "history page shows your stats and every roll" do
    sign_in @user
    DailyRoll.create!(user: @user, value: 900_001, rolled_on: Date.yesterday)
    DailyRoll.create!(user: @user, value: 300_001, rolled_on: 2.days.ago.to_date)

    get rng_history_path

    assert_response :success
    assert_match "900,001", response.body
    assert_match "300,001", response.body
    assert_match "Lifetime total", response.body
    assert_match "Yesterday", response.body
  end

  test "history page requires sign in" do
    get rng_history_path

    assert_redirected_to root_path
  end

  test "leaderboard page marks your roll on the podium" do
    sign_in @user
    DailyRoll.create!(user: @user, value: 99, rolled_on: Date.current)

    get rng_path

    assert_response :success
    assert_match "rng-board__pedestal--viewer", response.body
    assert_match "rng-board__you-tag", response.body
  end

  test "leaderboard page marks your roll in the list below the podium" do
    sign_in @user
    third = User.create!(email: "fourth@example.test", display_name: "fixture_four")
    [ users(:two), users(:three), third ].each_with_index do |u, i|
      DailyRoll.create!(user: u, value: 1_000 + i, rolled_on: Date.current)
    end
    DailyRoll.create!(user: @user, value: 5, rolled_on: Date.current)

    get rng_path

    assert_response :success
    assert_match "rng-board__row--viewer", response.body
  end
end
