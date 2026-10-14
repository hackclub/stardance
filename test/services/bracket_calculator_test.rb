require "test_helper"

class BracketCalculatorTest < ActiveSupport::TestCase
  test "leader always lands in the top bracket at full payout" do
    result = BracketCalculator.new([ { user: 1, total: 40 }, { user: 2, total: 10 } ], 1000).calculate

    leader = result[:results].find { |r| r[:user] == 1 }
    assert_equal "90-100%", leader[:bracket]
    assert_equal 1000, leader[:payout]
    assert_equal 100.0, leader[:percent]
  end

  test "assigns each bracket's payout multiplier relative to the leader's total" do
    leaderboard = [
      { user: :top, total: 100 },
      { user: :b, total: 89 },
      { user: :c, total: 74 },
      { user: :d, total: 59 },
      { user: :e, total: 44 },
      { user: :f, total: 29 },
      { user: :g, total: 14 },
      { user: :h, total: 6 },
      { user: :i, total: 5 },
      { user: :j, total: 0 }
    ]

    result = BracketCalculator.new(leaderboard, 1000).calculate
    payouts = result[:results].index_by { |r| r[:user] }.transform_values { |r| [ r[:bracket], r[:payout] ] }

    assert_equal [ "90-100%", 1000 ], payouts[:top]
    assert_equal [ "75-89%", 850 ], payouts[:b]
    assert_equal [ "60-74%", 700 ], payouts[:c]
    assert_equal [ "45-59%", 550 ], payouts[:d]
    assert_equal [ "30-44%", 400 ], payouts[:e]
    assert_equal [ "15-29%", 250 ], payouts[:f]
    assert_equal [ "6-14%", 100 ], payouts[:g]
    assert_equal [ "0-5%", 25 ], payouts[:i]
    assert_equal [ "<1%", 1 ], payouts[:j]
  end

  test "totals under 1% of the leader get a flat participation payout instead of the 0-5% bracket rate" do
    result = BracketCalculator.new([ { user: :leader, total: 1000 }, { user: :barely, total: 9 }, { user: :none, total: 0 } ], 1000).calculate
    payouts = result[:results].index_by { |r| r[:user] }

    assert_equal [ "<1%", 1 ], [ payouts[:barely][:bracket], payouts[:barely][:payout] ]
    assert_equal [ "<1%", 1 ], [ payouts[:none][:bracket], payouts[:none][:payout] ]
  end

  test "exactly 1% of the leader still gets the 0-5% bracket rate, not the flat payout" do
    result = BracketCalculator.new([ { user: :leader, total: 100 }, { user: :edge, total: 1 } ], 1000).calculate
    edge = result[:results].find { |r| r[:user] == :edge }

    assert_equal [ "0-5%", 25 ], [ edge[:bracket], edge[:payout] ]
  end

  test "raising the leader's total alone pushes everyone else's payout down" do
    before = BracketCalculator.new([ { user: :leader, total: 44 }, { user: :other, total: 40 } ], 1000).calculate
    other_before = before[:results].find { |r| r[:user] == :other }
    assert_equal [ "90-100%", 1000 ], [ other_before[:bracket], other_before[:payout] ]

    after = BracketCalculator.new([ { user: :leader, total: 100 }, { user: :other, total: 40 } ], 1000).calculate
    other_after = after[:results].find { |r| r[:user] == :other }

    assert_equal [ "30-44%", 400 ], [ other_after[:bracket], other_after[:payout] ]
    assert other_after[:payout] < other_before[:payout], "other's total didn't change, but their payout dropped because the leader pulled ahead"
  end

  test "percentages that fall between two bracket boundaries still get a bracket, not the bottom fallback" do
    # 184 / 246 = 0.747967..., strictly between the old 0.74/0.75 boundary gap.
    result = BracketCalculator.new([ { user: :leader, total: 246 }, { user: :mid, total: 184 } ], 1000).calculate
    mid = result[:results].find { |r| r[:user] == :mid }

    assert_equal [ "60-74%", 700 ], [ mid[:bracket], mid[:payout] ]
  end

  test "ties at the leader's total both get the top bracket" do
    result = BracketCalculator.new([ { user: :a, total: 20 }, { user: :b, total: 20 } ], 1000).calculate

    assert_equal [ "90-100%", "90-100%" ], result[:results].map { |r| r[:bracket] }
    assert_equal [ 1000, 1000 ], result[:results].map { |r| r[:payout] }
  end

  test "results are sorted by total descending" do
    result = BracketCalculator.new([ { user: :low, total: 5 }, { user: :high, total: 50 }, { user: :mid, total: 20 } ], 1000).calculate

    assert_equal [ :high, :mid, :low ], result[:results].map { |r| r[:user] }
  end

  test "total_distributed sums every result's payout" do
    result = BracketCalculator.new([ { user: :a, total: 10 }, { user: :b, total: 5 } ], 1000).calculate

    assert_equal result[:results].sum { |r| r[:payout] }, result[:total_distributed]
  end

  test "empty leaderboard calculates without dividing by zero" do
    result = BracketCalculator.new([], 1000).calculate

    assert_equal 1, result[:max_count]
    assert_equal [], result[:results]
    assert_equal 0, result[:total_distributed]
  end

  test "calculate_user_payout mirrors the payout calculate would assign" do
    calculator = BracketCalculator.new([ { user: :a, total: 100 } ], 1000)

    assert_equal 550, calculator.calculate_user_payout(50, 100)
    assert_equal 25, calculator.calculate_user_payout(5, 100)
    assert_equal 1, calculator.calculate_user_payout(0, 100)
  end

  test "brackets returns every tier's payout for the configured max_payout" do
    calculator = BracketCalculator.new([], 2000)

    assert_equal(
      [ 2000, 1700, 1400, 1100, 800, 500, 200, 50 ],
      calculator.brackets.map { |b| b[:payout] }
    )
  end
end
