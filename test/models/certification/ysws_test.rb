require "test_helper"

class Certification::YswsTest < ActiveSupport::TestCase
  # weekly_payout_projection is a pure function of a reviewer's lifetime total
  # and their pace hash, so these need no records.

  test "weekly_payout_projection prices a week that crosses a tier boundary" do
    # 780 devlogs banked before the week, 200 reviewed in it: 120 finish the 0.2
    # tier, the other 80 pay 0.3.
    projection = Certification::Ysws.weekly_payout_projection(
      lifetime_devlogs: 980,
      pace: pace_for(reviewed: 200, day_number: 7)
    )

    assert_equal 200, projection[:projected_devlogs]
    assert_equal 48.0, projection[:full]
  end

  test "weekly_payout_projection halves a week that misses the weekly goal" do
    projection = Certification::Ysws.weekly_payout_projection(
      lifetime_devlogs: 980,
      pace: pace_for(reviewed: 200, day_number: 7)
    )

    assert_not projection[:locked_in]
    assert_equal 24.0, projection[:payout]
  end

  test "weekly_payout_projection pays in full at exactly the goal pace" do
    projection = Certification::Ysws.weekly_payout_projection(
      lifetime_devlogs: 90,
      pace: pace_for(reviewed: 90, day_number: 3)
    )

    assert projection[:locked_in]
    assert_equal Certification::Ysws::WEEKLY_DEVLOG_GOAL, projection[:projected_devlogs]
    assert_equal 42.0, projection[:full]
    assert_equal projection[:full], projection[:payout]
  end

  test "weekly_payout_projection rounds away the float noise of two tier lookups" do
    projection = Certification::Ysws.weekly_payout_projection(
      lifetime_devlogs: 212,
      pace: pace_for(reviewed: 211, day_number: 7)
    )

    assert_equal 42.2, projection[:full]
  end

  test "weekly_payout_projection is empty for a reviewer who hasn't started the week" do
    projection = Certification::Ysws.weekly_payout_projection(
      lifetime_devlogs: 500,
      pace: pace_for(reviewed: 0, day_number: 4)
    )

    assert_equal 0, projection[:projected_devlogs]
    assert_equal 0.0, projection[:full]
    assert_equal 0.0, projection[:payout]
    assert_not projection[:locked_in]
  end

  test "weekly_payout_projection still prices a full week for a reviewer with no pace" do
    # Nothing to extrapolate, so the panel falls back to what a full week is
    # worth from where they stand: 210 more devlogs, all inside the 0.2 tier.
    projection = Certification::Ysws.weekly_payout_projection(
      lifetime_devlogs: 500,
      pace: pace_for(reviewed: 0, day_number: 4)
    )

    assert_equal 42.0, projection[:goal_payout]
    assert_equal 21.0, projection[:goal_payout_halved]
  end

  test "goal_payout prices a full week across a tier boundary" do
    # 780 banked, so a 210-devlog week finishes the 0.2 tier and spills into 0.3.
    projection = Certification::Ysws.weekly_payout_projection(
      lifetime_devlogs: 780,
      pace: pace_for(reviewed: 0, day_number: 1)
    )

    assert_equal 51.0, projection[:goal_payout]
  end

  test "locked_in always agrees with the projection reaching the weekly goal" do
    # The panel reads locked_in off the daily pace flag rather than re-testing
    # the projection, so the two must never disagree — otherwise a reviewer can
    # be told they're on pace and have the same week halved.
    (1..Certification::Ysws::REVIEW_WEEK_DAYS).each do |day_number|
      (0..400).each do |reviewed|
        projection = Certification::Ysws.weekly_payout_projection(
          lifetime_devlogs: reviewed,
          pace: pace_for(reviewed: reviewed, day_number: day_number)
        )

        assert_equal projection[:projected_devlogs] >= Certification::Ysws::WEEKLY_DEVLOG_GOAL,
                     projection[:locked_in],
                     "day #{day_number}, #{reviewed} reviewed: projected " \
                     "#{projection[:projected_devlogs]} vs locked_in #{projection[:locked_in]}"
      end
    end
  end

  private

  # Mirrors Certification::Ysws.reviewer_devlog_pace, so the projection is fed
  # the same shape the dashboard hands it without touching the database.
  def pace_for(reviewed:, day_number:)
    {
      reviewed: reviewed,
      day_number: day_number,
      daily_average: reviewed / day_number.to_f,
      needed_today: [ (Certification::Ysws::DEVLOG_REVIEW_GOAL_PER_DAY * day_number) - reviewed, 0 ].max
    }
  end
end
