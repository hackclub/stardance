require "test_helper"

class StickyStreaksControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:sticky_streaks)
    @user = create_user(slack_id: "U-sticky-ctrl", display_name: "stickyctrl", verified: true)
    @user.identities.create!(provider: "hackatime", uid: "ht-sticky", access_token: "fake")
    sign_in @user
  end

  teardown { Flipper.disable(:sticky_streaks) }

  test "starting the challenge opens a first run on the user's current streak day" do
    post sticky_streak_path

    streak = @user.sticky_streaks.sole
    assert_predicate streak, :kind_first?
    assert_equal @user.streak_today_date, streak.started_on
  end

  test "the challenge cannot be started while it is switched off" do
    Flipper.disable(:sticky_streaks)

    post sticky_streak_path

    assert_empty @user.sticky_streaks
    assert_equal "Sticky Streaks aren't available yet.", flash[:alert]
  end

  test "a live first run blocks a second post" do
    post sticky_streak_path
    post sticky_streak_path

    assert_equal 1, @user.sticky_streaks.count
    assert_equal "You don't have a Sticky Streak to start right now.", flash[:alert]
  end

  test "a broken first run can be restarted once, and only once" do
    break_first_run

    post sticky_streak_path
    assert_predicate @user.sticky_streaks.kind_retry.sole, :kind_retry?
    assert_equal @user.streak_today_date, @user.sticky_streaks.kind_retry.sole.started_on

    post sticky_streak_path
    assert_equal 2, @user.sticky_streaks.count
    assert_equal "You don't have a Sticky Streak to start right now.", flash[:alert]
  end

  test "a broken restart is the end of the line" do
    broken_run(kind: :first, days_ago: 10)
    broken_run(kind: :retry)

    post sticky_streak_path

    assert_equal 2, @user.sticky_streaks.count
    assert_equal "You don't have a Sticky Streak to start right now.", flash[:alert]
  end

  test "reaching day 21 opens a second streak instead of a restart" do
    finished_run(kind: :first)

    post sticky_streak_path

    assert_predicate @user.sticky_streaks.kind_second.sole, :kind_second?
  end

  test "a second streak follows a restart that went the distance" do
    broken_run(kind: :first, days_ago: 45)
    finished_run(kind: :retry)

    post sticky_streak_path

    assert_predicate @user.sticky_streaks.kind_second.sole, :kind_second?
  end

  test "a broken second streak cannot be restarted" do
    finished_run(kind: :first, days_ago: 45)
    broken_run(kind: :second)

    post sticky_streak_path

    assert_equal 2, @user.sticky_streaks.count
    assert_equal "You don't have a Sticky Streak to start right now.", flash[:alert]
  end

  private

  def break_first_run = broken_run(kind: :first)

  # A run whose settled days went uncoded, so it has already failed. Windows
  # are kept apart so one run's coding time cannot rescue another's days.
  def broken_run(kind:, days_ago: 2)
    @user.sticky_streaks.create!(kind: kind, started_on: @user.streak_today_date - days_ago)
  end

  # A run that reached day 21 with every day coded.
  def finished_run(kind:, days_ago: StickyStreak::LENGTH)
    run = @user.sticky_streaks.create!(kind: kind, started_on: @user.streak_today_date - days_ago)
    (1..StickyStreak::LENGTH).each do |day|
      StreakActivity.create!(user: @user, activity_date: run.date_for(day),
                             coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    end
    run
  end
end
