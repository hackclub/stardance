require "test_helper"

class Growth::SnapshotBuilderTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 9, 30)

  setup do
    @users = {}
  end

  test "sorts each user into one state and records yesterday-to-today moves" do
    active("new", 0, sources: [ "vote" ])
    active("current", 3, 1, 0)
    active("at_risk_wau", 2)
    active("wau_lost", 7)
    active("reactivated", 10, 0)
    active("resurrected", 40, 0)
    active("dormant", 35)
    active("future", -1)

    Growth::SnapshotBuilder.new(DAY).call
    engaged = GrowthDailySnapshot.find_by!(metric: "engaged", snapshot_on: DAY)

    assert_equal(
      { "new" => 1, "current" => 1, "reactivated" => 1, "resurrected" => 1, "at_risk_wau" => 1, "at_risk_mau" => 1, "dormant" => 1 },
      GrowthDailySnapshot::STATES.index_with { |state| engaged.count_for(state) }
    )
    assert_equal 4, engaged.dau
    assert_equal 5, engaged.wau
    assert_equal 6, engaged.mau
    assert_equal(
      {
        "current" => { "current" => 1 },
        "at_risk_wau" => { "at_risk_wau" => 1, "at_risk_mau" => 1 },
        "at_risk_mau" => { "reactivated" => 1 },
        "dormant" => { "resurrected" => 1, "dormant" => 1 }
      },
      engaged.transitions
    )
    assert_in_delta 0.5, engaged.rate("wau_loss")
    assert_nil engaged.rate("nurr")
  end

  test "each metric only counts its own sources" do
    active("voter", 0, sources: [ "vote" ])

    Growth::SnapshotBuilder.new(DAY).call

    assert_equal 1, GrowthDailySnapshot.find_by!(metric: "vote", snapshot_on: DAY).new_users
    assert_equal 0, GrowthDailySnapshot.find_by!(metric: "coding", snapshot_on: DAY).new_users
    assert_equal GrowthDailySnapshot::METRICS.size, GrowthDailySnapshot.where(snapshot_on: DAY).count
  end

  test "leaves out banned users and guests" do
    active("banned", 0).update!(banned: true)
    active("guest", 0, hca_linked: false)

    Growth::SnapshotBuilder.new(DAY).call

    assert_equal 0, GrowthDailySnapshot.find_by!(metric: "engaged", snapshot_on: DAY).new_users
  end

  test "rebuilding a day replaces its snapshot" do
    active("current", 1, 0)
    Growth::SnapshotBuilder.new(DAY).call
    Growth::SnapshotBuilder.new(DAY).call

    assert_equal 1, GrowthDailySnapshot.where(metric: "engaged", snapshot_on: DAY).count
  end

  private

  # A user active on each of `days_ago` days before DAY.
  def active(name, *days_ago, sources: [ "coding" ], hca_linked: true)
    user = create_user(slack_id: "U_GROWTH_#{name.upcase}", display_name: "growth_#{name}", hca_linked:)
    days_ago.each { |ago| UserActivityDay.create!(user:, active_on: DAY - ago, sources:) }
    user
  end
end
