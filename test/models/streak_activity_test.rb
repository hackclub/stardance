# == Schema Information
#
# Table name: streak_activities
#
#  id                   :bigint           not null, primary key
#  activity_date        :date             not null
#  coded_seconds        :integer          default(0), not null
#  manual_credit_at     :datetime
#  manual_credit_reason :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  manual_credit_by_id  :bigint
#  user_id              :bigint           not null
#
# Indexes
#
#  index_streak_activities_on_manual_credit_by_id        (manual_credit_by_id)
#  index_streak_activities_on_user_id                    (user_id)
#  index_streak_activities_on_user_id_and_activity_date  (user_id,activity_date) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (manual_credit_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class StreakActivityTest < ActiveSupport::TestCase
  setup do
    @user = users(:three)
    @user.update!(timezone: "America/New_York")
  end

  teardown do
    @user.streak_activities.destroy_all
    @user.update!(timezone: nil)
  end

  test "streak_date_for shifts by 2 hours" do
    tz = "America/New_York"
    assert_equal Date.new(2026, 6, 21), StreakActivity.streak_date_for(Time.zone.parse("2026-06-22 05:30:00 UTC"), tz)
    assert_equal Date.new(2026, 6, 22), StreakActivity.streak_date_for(Time.zone.parse("2026-06-22 06:30:00 UTC"), tz)
  end

  test "streak_date_for defaults to UTC when timezone is nil" do
    assert_equal Date.new(2026, 6, 21), StreakActivity.streak_date_for(Time.zone.parse("2026-06-22 01:30:00 UTC"), nil)
  end

  test "completed?" do
    assert StreakActivity.new(coded_seconds: 300).completed?
    assert_not StreakActivity.new(coded_seconds: 299).completed?
  end

  test "a credited day counts as completed without any coding time" do
    day = @user.streak_today_date - 1.day

    activity = StreakActivity.credit!(user: @user, date: day, granted_by: helper, reason: "Hackatime lost the heartbeats")

    assert_predicate activity, :completed?
    assert_predicate activity, :manually_credited?
    assert_equal 0, activity.coded_seconds
    assert_includes @user.streak_activities.completed, activity
  end

  test "crediting a day rebuilds the streak count through it" do
    today = @user.streak_today_date
    StreakActivity.create!(user: @user, activity_date: today, coded_seconds: 400)
    StreakActivity.create!(user: @user, activity_date: today - 2.days, coded_seconds: 400)
    @user.recalculate_streak!

    assert_equal 1, @user.current_streak, "the gap at yesterday holds the run to today"

    StreakActivity.credit!(user: @user, date: today - 1.day, granted_by: helper, reason: "Hackatime outage")

    assert_equal 3, @user.reload.current_streak
  end

  test "a credit outlives a sync rewriting the day's coding time" do
    day = @user.streak_today_date - 1.day
    activity = StreakActivity.credit!(user: @user, date: day, granted_by: helper, reason: "Hackatime outage")

    # What sync_for_user! does to every day it re-reads from Hackatime.
    activity.update!(coded_seconds: 0)

    assert_predicate activity.reload, :completed?
  end

  test "revoking a credit keeps the coding time the day really had" do
    day = @user.streak_today_date - 1.day
    activity = StreakActivity.create!(user: @user, activity_date: day, coded_seconds: 120)
    StreakActivity.credit!(user: @user, date: day, granted_by: helper, reason: "granted by mistake")

    activity.reload.revoke_credit!

    assert_not_predicate activity, :completed?
    assert_not_predicate activity, :manually_credited?
    assert_equal 120, activity.coded_seconds
  end

  test "a credit records who granted it and why" do
    activity = StreakActivity.credit!(user: @user, date: @user.streak_today_date, granted_by: helper, reason: "confirmed in #stardance-help")

    assert_equal helper, activity.manual_credit_by
    assert_equal "confirmed in #stardance-help", activity.manual_credit_reason
    assert_includes activity.versions.last.object_changes.keys, "manual_credit_at",
                    "the credit has to be reconstructable from the audit trail"
  end

  test "current_streak with consecutive days" do
    today = @user.streak_today_date
    (-3..0).each { |d| StreakActivity.create!(user: @user, activity_date: today + d.days, coded_seconds: 400) }
    @user.recalculate_streak!
    assert_equal 4, @user.current_streak
  end

  test "current_streak breaks on gap" do
    today = @user.streak_today_date
    StreakActivity.create!(user: @user, activity_date: today, coded_seconds: 400)
    StreakActivity.create!(user: @user, activity_date: today - 1.day, coded_seconds: 400)
    StreakActivity.create!(user: @user, activity_date: today - 3.days, coded_seconds: 400)
    @user.recalculate_streak!
    assert_equal 2, @user.current_streak
  end

  test "current_streak counts from yesterday when today not completed" do
    today = @user.streak_today_date
    StreakActivity.create!(user: @user, activity_date: today, coded_seconds: 100)
    StreakActivity.create!(user: @user, activity_date: today - 1.day, coded_seconds: 400)
    StreakActivity.create!(user: @user, activity_date: today - 2.days, coded_seconds: 400)
    @user.recalculate_streak!
    assert_equal 2, @user.current_streak
  end

  test "current_streak is zero with no activities" do
    assert_equal 0, @user.current_streak
  end

  test "longest_streak" do
    today = @user.streak_today_date
    # 3-day run, gap, 5-day run
    (-2..0).each { |d| StreakActivity.create!(user: @user, activity_date: today + d.days, coded_seconds: 400) }
    (-8..-4).each { |d| StreakActivity.create!(user: @user, activity_date: today + d.days, coded_seconds: 400) }
    assert_equal 5, @user.longest_streak
  end

  test "streak_week_activities returns 7 days starting Sunday" do
    week = @user.streak_week_activities
    assert_equal 7, week.length
    assert_equal "S", week.first[:day_letter]
    assert_equal "S", week.last[:day_letter]
  end

  test "streak_week_activities marks today" do
    today_entry = @user.streak_week_activities.find { |d| d[:today] }
    assert today_entry
    assert_equal @user.streak_today_date, today_entry[:date]
  end

  test "streak_month_calendar returns full grid with streak bars" do
    today = @user.streak_today_date
    (-2..0).each { |d| StreakActivity.create!(user: @user, activity_date: today + d.days, coded_seconds: 400) }

    cal = @user.streak_month_calendar(today.year, today.month)
    assert cal.length >= 28
    assert cal.any? { |d| d[:completed] }
    assert cal.any? { |d| d[:streak_left] || d[:streak_right] }
  end

  test "calendar and week can reuse preloaded activities without querying" do
    today = @user.streak_today_date
    activity = StreakActivity.create!(user: @user, activity_date: today, coded_seconds: 400)
    activities = { today => activity }
    queries = []
    record_query = ->(*args) { queries << args.last[:sql] if args.last[:sql].match?(/streak_activities/i) }

    ActiveSupport::Notifications.subscribed(record_query, "sql.active_record") do
      assert @user.streak_week_activities(activities: activities, today: today).find { |day| day[:today] }[:completed]
      assert @user.streak_month_calendar(today.year, today.month, activities: activities, today: today)
        .find { |day| day[:today] }[:completed]
    end

    assert_empty queries
  end

  private

  def helper
    @helper ||= create_user(slack_id: "U-streak-helper", display_name: "streakhelper").tap { |u| u.grant_role!(:helper) }
  end
end
