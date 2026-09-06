# == Schema Information
#
# Table name: daily_rolls
#
#  id           :bigint           not null, primary key
#  reroll_value :integer
#  rolled_on    :date             not null
#  value        :integer          not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_daily_rolls_on_rolled_on_and_value    (rolled_on,value)
#  index_daily_rolls_on_user_id                (user_id)
#  index_daily_rolls_on_user_id_and_rolled_on  (user_id,rolled_on) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class DailyRollTest < ActiveSupport::TestCase
  setup do
    @winner = create_user(slack_id: "U_ROLL_WINNER", display_name: "roll_winner")
    @loser  = create_user(slack_id: "U_ROLL_LOSER", display_name: "roll_loser")
  end

  test "topped_a_day is true only for the day's highest roll" do
    DailyRoll.create!(user: @winner, value: 100, rolled_on: 2.days.ago.to_date)
    DailyRoll.create!(user: @loser, value: 1, rolled_on: 2.days.ago.to_date)

    assert DailyRoll.topped_a_day(@winner)
    assert_not DailyRoll.topped_a_day(@loser)
  end

  test "grant_winner_achievements! awards rng_winner to each day's topper only" do
    DailyRoll.create!(user: @winner, value: 100, rolled_on: 2.days.ago.to_date)
    DailyRoll.create!(user: @loser, value: 1, rolled_on: 2.days.ago.to_date)

    DailyRoll.grant_winner_achievements!

    assert @winner.reload.earned_achievement?(:rng_winner)
    assert_not @loser.reload.earned_achievement?(:rng_winner)
  end

  test "grant_winner_achievements! is idempotent" do
    DailyRoll.create!(user: @winner, value: 100, rolled_on: 2.days.ago.to_date)

    DailyRoll.grant_winner_achievements!
    assert_no_difference -> { User::Achievement.where(achievement_slug: "rng_winner").count } do
      DailyRoll.grant_winner_achievements!
    end
  end

  test "grant_winner_achievements! ignores today's still-open board" do
    DailyRoll.create!(user: @winner, value: 100, rolled_on: Date.current)

    DailyRoll.grant_winner_achievements!

    assert_not @winner.reload.earned_achievement?(:rng_winner)
  end

  test "grant_winner_achievements! ignores yesterday's board" do
    DailyRoll.create!(user: @winner, value: 100, rolled_on: 1.day.ago.to_date)

    DailyRoll.grant_winner_achievements!

    assert_not @winner.reload.earned_achievement?(:rng_winner)
  end

  test "first_win returns the winning roll from the user's earliest #1 finish" do
    earlier_win = DailyRoll.create!(user: @winner, value: 100, rolled_on: 5.days.ago.to_date)
    DailyRoll.create!(user: @winner, value: 100, rolled_on: 2.days.ago.to_date)
    DailyRoll.create!(user: @loser, value: 1, rolled_on: 5.days.ago.to_date)
    DailyRoll.create!(user: @loser, value: 1, rolled_on: 2.days.ago.to_date)

    assert_equal earlier_win, DailyRoll.first_win(@winner)
  end

  test "first_win returns nil for a user who never topped a day" do
    DailyRoll.create!(user: @loser, value: 1, rolled_on: 2.days.ago.to_date)

    assert_nil DailyRoll.first_win(@loser)
  end
end
