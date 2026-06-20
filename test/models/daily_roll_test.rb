# == Schema Information
#
# Table name: daily_rolls
#
#  id         :bigint           not null, primary key
#  rolled_on  :date             not null
#  value      :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
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
    @user = users(:one)
  end

  test "roll! creates a positive roll for today within range" do
    roll = DailyRoll.roll!(@user)

    assert roll.persisted?
    assert_equal Date.current, roll.rolled_on
    assert_includes(0..DailyRoll::MAX_VALUE, roll.value)
  end

  test "random_value always stays within 0..MAX_VALUE" do
    1_000.times do
      assert_includes(0..DailyRoll::MAX_VALUE, DailyRoll.random_value)
    end
  end

  test "random_value keeps most rolls short so the digit count is a surprise" do
    magnitudes = Array.new(2_000) { DailyRoll.random_value.abs }

    # The growth process biases toward few digits; a uniform draw would put
    # nearly everything in the billions.
    short = magnitudes.count { |m| m < 1_000 }
    long = magnitudes.count { |m| m >= 1_000_000 }
    assert short > long, "expected short rolls (#{short}) to outnumber long ones (#{long})"
  end

  test "roll! returns the existing roll on a second attempt the same day" do
    first = DailyRoll.roll!(@user)

    assert_no_difference "DailyRoll.count" do
      assert_equal first, DailyRoll.roll!(@user)
    end
  end

  test "a roll's value, date, and owner cannot be changed after creation" do
    roll = DailyRoll.create!(user: @user, value: 100, rolled_on: Date.current)

    assert_raises(ActiveRecord::ReadonlyAttributeError) { roll.update(value: 999_999) }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { roll.update(rolled_on: Date.yesterday) }
    assert_raises(ActiveRecord::ReadonlyAttributeError) { roll.update(user: users(:two)) }

    assert_equal 100, roll.reload.value
  end

  test "the database rejects a second roll for the same user and day" do
    DailyRoll.create!(user: @user, value: 1, rolled_on: Date.current)

    assert_raises(ActiveRecord::RecordNotUnique) do
      # Skip the model validation to prove the DB unique index is the backstop.
      dup = DailyRoll.new(user: @user, value: 2, rolled_on: Date.current)
      dup.save!(validate: false)
    end
  end

  test "a user can roll again on a new day" do
    DailyRoll.create!(user: @user, value: 50, rolled_on: Date.yesterday)

    assert_difference "DailyRoll.count", 1 do
      DailyRoll.roll!(@user)
    end
  end

  test "leaderboard orders by value desc and breaks ties by earliest roll" do
    low = DailyRoll.create!(user: users(:one), value: 5, rolled_on: Date.current)
    early_high = DailyRoll.create!(user: users(:two), value: 90, rolled_on: Date.current, created_at: 2.hours.ago)
    late_high = DailyRoll.create!(user: users(:three), value: 90, rolled_on: Date.current)

    assert_equal [ early_high, late_high, low ], DailyRoll.leaderboard.to_a
  end

  test "leaderboard only includes rolls from the given day" do
    DailyRoll.create!(user: users(:one), value: 99, rolled_on: Date.yesterday)
    today = DailyRoll.create!(user: users(:two), value: 5, rolled_on: Date.current)

    assert_equal [ today ], DailyRoll.leaderboard.to_a
  end

  test "rank counts higher rolls and earlier ties" do
    DailyRoll.create!(user: users(:one), value: 90, rolled_on: Date.current, created_at: 1.hour.ago)
    tied = DailyRoll.create!(user: users(:two), value: 90, rolled_on: Date.current)
    low = DailyRoll.create!(user: users(:three), value: 10, rolled_on: Date.current)

    assert_equal 2, tied.rank
    assert_equal 3, low.rank
  end

  test "flavor picks a variant from the matching magnitude tier" do
    { 0 => 0, 7 => 1, 42 => 10, 4_200 => 1_000, DailyRoll::MAX_VALUE => DailyRoll::MAX_VALUE }.each do |value, threshold|
      variants = DailyRoll::FLAVORS.find { |t, _| t == threshold }.last
      assert_includes variants, DailyRoll.new(value: value).flavor
    end
  end

  test "flavor varies across rolls in the same tier" do
    flavors = (1..9).map { |v| DailyRoll.new(value: v).flavor }
    assert flavors.uniq.size > 1, "expected variety within a tier, got #{flavors.uniq.inspect}"
  end

  test "day_label numbers days from launch and marks pre-launch as -1" do
    assert_equal "day 1", DailyRoll.new(rolled_on: DailyRoll::LAUNCH_ON).day_label
    assert_equal "day 2", DailyRoll.new(rolled_on: DailyRoll::LAUNCH_ON + 1).day_label
    assert_equal "day 8", DailyRoll.new(rolled_on: DailyRoll::LAUNCH_ON + 7).day_label
    assert_equal "day -1", DailyRoll.new(rolled_on: DailyRoll::LAUNCH_ON - 1).day_label
  end

  test "tone tiers the number by magnitude for colour" do
    assert_equal "low", DailyRoll.new(value: 9).tone
    assert_equal "mid", DailyRoll.new(value: 500).tone
    assert_equal "high", DailyRoll.new(value: 25_000).tone
    assert_equal "cosmic", DailyRoll.new(value: 5_000_000).tone
  end

  test "rejects values outside 0..MAX_VALUE" do
    assert_not DailyRoll.new(user: @user, value: DailyRoll::MAX_VALUE + 1, rolled_on: Date.current).valid?
    assert_not DailyRoll.new(user: @user, value: -1, rolled_on: Date.current).valid?
    assert DailyRoll.new(user: @user, value: 0, rolled_on: Date.current).valid?
    assert DailyRoll.new(user: @user, value: 50, rolled_on: Date.current).valid?
  end
end
