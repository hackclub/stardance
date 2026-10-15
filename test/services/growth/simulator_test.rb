require "test_helper"

class Growth::SimulatorTest < ActiveSupport::TestCase
  test "ranks retention levers by the DAU they add" do
    levers = Growth::Simulator.new([ snapshot ] * 3, signups: "flat").levers

    assert levers.all? { |lever| lever.lift.positive? }
    assert_equal levers.map(&:lift).sort.reverse, levers.map(&:lift)
    assert_equal "curr", levers.first.rate
    assert_in_delta 0.8, levers.find { |lever| lever.rate == "curr" }.current_rate
  end

  test "rates the window never saw are not levers" do
    levers = Growth::Simulator.new([ snapshot ]).levers.map(&:rate)

    assert_not_includes levers, "surr"
    assert_not_includes levers, "rurr"
  end

  # Duolingo's example: 80% retention and one signup a day per five active
  # users holds DAU flat, and a better retention rate then compounds.
  test "word of mouth holds a balanced DAU steady and compounds an improvement" do
    balanced = GrowthDailySnapshot.new(
      metric: "engaged", snapshot_on: Date.new(2026, 9, 30), new_users: 20, current_users: 80,
      transitions: {
        "new" => { "current" => 16, "at_risk_wau" => 4 },
        "current" => { "current" => 64, "at_risk_wau" => 16 }
      }
    )
    simulator = Growth::Simulator.new([ balanced ] * 2)
    curr = simulator.levers.find { |lever| lever.rate == "curr" }

    assert_in_delta 0.2, simulator.signups_per_dau
    simulator.baseline.each { |dau| assert_in_delta 100, dau, 0.001 }
    gains = curr.daily_dau.map { |dau| dau - 100 }
    assert gains.each_cons(2).all? { |earlier, later| later > earlier }
    assert curr.cost_of_waiting.positive?
  end

  test "word of mouth makes the same improvement worth more than flat signups" do
    lift = ->(signups) { Growth::Simulator.new([ snapshot ] * 3, signups:).levers.find { |lever| lever.rate == "curr" }.lift }

    assert_operator lift.call("word_of_mouth"), :>, lift.call("flat")
  end

  private

  def snapshot
    GrowthDailySnapshot.new(
      metric: "engaged", snapshot_on: Date.new(2026, 9, 30),
      new_users: 10, current_users: 100, at_risk_wau: 50, at_risk_mau: 40, dormant_users: 200,
      transitions: {
        "new" => { "current" => 4, "at_risk_wau" => 6 },
        "current" => { "current" => 80, "at_risk_wau" => 20 },
        "at_risk_wau" => { "current" => 5, "at_risk_wau" => 35, "at_risk_mau" => 10 },
        "at_risk_mau" => { "reactivated" => 2, "at_risk_mau" => 33, "dormant" => 5 },
        "dormant" => { "resurrected" => 1, "dormant" => 199 }
      }
    )
  end
end
