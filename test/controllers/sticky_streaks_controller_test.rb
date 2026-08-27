require "test_helper"

class StickyStreaksControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:sticky_streaks)
    @user = create_user(slack_id: "U-sticky-ctrl", display_name: "stickyctrl", verified: true)
    @user.identities.create!(provider: "hackatime", uid: "ht-sticky", access_token: "fake")
    sign_in @user
  end

  teardown { Flipper.disable(:sticky_streaks) }

  test "starting the challenge opens a run on the user's current streak day" do
    post sticky_streak_path

    streak = @user.reload.sticky_streak
    assert_not_nil streak
    assert_equal @user.streak_today_date, streak.started_on
  end

  test "the challenge cannot be started while it is switched off" do
    Flipper.disable(:sticky_streaks)

    post sticky_streak_path

    assert_nil @user.reload.sticky_streak
    assert_equal "Sticky Streaks aren't available yet.", flash[:alert]
  end

  test "the challenge can only be started once" do
    post sticky_streak_path
    post sticky_streak_path

    assert_equal 1, StickyStreak.where(user: @user).count
    assert_equal "You have already started your Sticky Streak.", flash[:alert]
  end
end
