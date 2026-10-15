require "test_helper"

class Growth::ActivityBuilderTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 9, 30)

  setup do
    @user = create_user(slack_id: "U_GROWTH_ACTIVITY", display_name: "growth_activity")
  end

  test "records coding days that met the streak goal and daily rolls" do
    StreakActivity.create!(user: @user, activity_date: DAY, coded_seconds: StreakActivity::DAILY_GOAL_SECONDS)
    StreakActivity.create!(user: @user, activity_date: DAY - 1, coded_seconds: StreakActivity::DAILY_GOAL_SECONDS - 1)
    DailyRoll.create!(user: @user, rolled_on: DAY, value: 3)

    Growth::ActivityBuilder.new(from: DAY - 1, to: DAY).call

    assert_equal [ DAY ], UserActivityDay.where(user: @user).pluck(:active_on)
    assert_equal %w[coding daily_roll], UserActivityDay.find_by!(user: @user, active_on: DAY).sources
  end

  test "keeps sources already on the day and is safe to re-run" do
    UserActivityDay.merge_sources!([ [ @user.id, DAY, "visit" ] ])
    DailyRoll.create!(user: @user, rolled_on: DAY, value: 3)

    2.times { Growth::ActivityBuilder.new(from: DAY, to: DAY).call }

    assert_equal %w[daily_roll visit], UserActivityDay.find_by!(user: @user, active_on: DAY).sources
  end

  test "a visit is written once per user per day" do
    with_memory_cache do
      2.times { UserActivityDay.track_visit(@user.id) }
    end

    assert_equal [ "visit" ], UserActivityDay.find_by!(user: @user, active_on: UserActivityDay.today).sources
  end

  private

  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end
end
