require "test_helper"

# The one-time site-wide announcement for the Sticky Streak challenge.
class StickyStreakPromoTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:sticky_streaks)
    @user = create_user(slack_id: "U-promo", display_name: "promo")
    @user.update!(onboarded_at: Time.current)
    @user.identities.create!(provider: "hackatime", uid: "ht-promo", access_token: "fake")
    sign_in @user
  end

  teardown { Flipper.disable(:sticky_streaks) }

  test "it pops up for someone who could start a run" do
    get home_path

    assert_response :success
    assert_select "dialog.sticky-promo[data-dismissable-open-value='true']"
  end

  test "dismissing it keeps it away" do
    post my_dismissals_path, params: { thing_name: "sticky_streak_intro" }

    get home_path

    assert_response :success
    assert_select "dialog.sticky-promo", count: 0
  end

  test "it does not nag someone already running one" do
    StickyStreak.create!(user: @user, started_on: @user.streak_today_date)

    get home_path

    assert_response :success
    assert_select "dialog.sticky-promo", count: 0
  end

  test "it stays hidden while the challenge is switched off" do
    Flipper.disable(:sticky_streaks)

    get home_path

    assert_response :success
    assert_select "dialog.sticky-promo", count: 0
  end

  test "it stays hidden for users with no Hackatime to streak on" do
    @user.hackatime_identity.destroy!

    get home_path

    assert_response :success
    assert_select "dialog.sticky-promo", count: 0
  end
end
