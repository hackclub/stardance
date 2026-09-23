require "test_helper"

class BukuX3RefreshTest < ActiveSupport::TestCase
  include BukuX3Ships

  setup do
    Flipper.disable(:bukux2)
    Flipper.disable(:bukux3)
    @buku = users(:one)
    @human = users(:two)
    @cutoff = Time.zone.parse("2026-10-01 12:00")
    travel_to @cutoff + 3.days
    @event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: @cutoff)
    Flipper.enable(:bukux3)
  end

  teardown do
    Flipper.disable(:bukux2)
    Flipper.disable(:bukux3)
    travel_back
  end

  test "an empty event replays to the 25 percent starting balance" do
    @event.update!(visual_intensity: 50)
    assert_no_difference "BukuX3::Contribution.count" do
      refresh
    end
    assert_equal 25, @event.reload.percent
    assert_equal 50, @event.visual_intensity, "accounting must not overwrite the admin visual setting"
    assert_equal BukuX3::Event::STARTING_DESTRUCTION_MINUTES, @event.destruction_minutes
    assert_equal({ buku: 0, bean: 0 }, @event.team_hours)
  end

  test "team totals count approved hours without the starting damage or boundary clamping" do
    reviewed_ship(user: @buku, minutes: 6000 * 60, at: @cutoff + 1.hour)
    reviewed_ship(user: @human, minutes: 90, at: @cutoff + 2.hours)
    refresh
    assert_equal({ buku: 6000, bean: 1.5 }, @event.reload.team_hours)
    @buku.update_columns(banned: true)
    refresh
    assert_equal({ buku: 0, bean: 1.5 }, @event.reload.team_hours)
  end

  test "equal approved hours bring the tug back to the starting balance" do
    reviewed_ship(user: @buku, minutes: 500 * 60, at: @cutoff + 1.hour)
    reviewed_ship(user: @human, minutes: 500 * 60, at: @cutoff + 2.hours)
    refresh
    assert_equal 25, @event.reload.percent
  end

  test "buku hours damage the site and human hours restore it at 50 hours per percent" do
    reviewed_ship(user: @buku, minutes: 100 * 60, at: @cutoff + 1.hour)
    reviewed_ship(user: @human, minutes: 25 * 60, at: @cutoff + 2.hours)

    refresh

    assert_equal 26.5, @event.reload.percent
    assert_equal 2, @event.contributions.count
    assert @event.contributions.find_by!(user: @buku).buku?
    assert_not @event.contributions.find_by!(user: @human).buku?
  end

  test "ships before or at the cutoff never count even when reviewed later" do
    reviewed_ship(user: @buku, minutes: 600, at: @cutoff - 1.second, reviewed_at: @cutoff + 1.hour)
    reviewed_ship(user: @buku, minutes: 600, at: @cutoff, reviewed_at: @cutoff + 1.hour)
    reviewed_ship(user: @buku, minutes: 60, at: @cutoff + 1.second)
    refresh
    assert_equal 1, @event.contributions.count
    assert_equal BukuX3::Event::STARTING_DESTRUCTION_MINUTES + 60, @event.reload.destruction_minutes
  end

  test "retries and reloads do not duplicate contributions or audit versions" do
    reviewed_ship(user: @buku, minutes: 3000, at: @cutoff + 1.hour)
    refresh
    versions = PaperTrail::Version.count
    3.times { refresh }
    assert_equal 1, @event.contributions.count
    assert_equal 26, @event.reload.percent
    assert_equal versions, PaperTrail::Version.count
  end

  test "reconciles approved minutes instead of raw time and applies fraud deductions" do
    review = reviewed_ship(user: @buku, minutes: 6000, approved: 3000, at: @cutoff + 1.hour)
    refresh
    assert_equal 26, @event.reload.percent
    Certification::Integrity.create!(ship_event: review.post_ship_event, reviewer: @human,
                                     status: :deducted, deduction_minutes: 1500)
    refresh
    assert_equal 25.5, @event.reload.percent
    review.integrity_check.update!(deduction_minutes: 9000)
    refresh
    assert_equal 25, @event.reload.percent
  end

  test "pending incomplete and under-minimum reviews do not count" do
    reviewed_ship(user: @buku, minutes: 6000, at: @cutoff + 1.hour, reviewed_at: nil)
    reviewed_ship(user: @buku, minutes: 100, approved: 5, at: @cutoff + 2.hours)
    refresh
    assert_empty @event.contributions
    assert_equal 25, @event.reload.percent
  end

  test "bans remove contributions and unbans restore them" do
    reviewed_ship(user: @buku, minutes: 3000, at: @cutoff + 1.hour)
    refresh
    @buku.update_columns(banned: true)
    refresh
    assert_equal 25, @event.reload.percent
    assert_equal 0, @event.contributions.sole.minutes
    @buku.update_columns(banned: false)
    refresh
    assert_equal 26, @event.reload.percent
  end

  test "reopening or rejecting a previously counted review removes its effect" do
    review = reviewed_ship(user: @buku, minutes: 3000, at: @cutoff + 1.hour)
    refresh
    review.update!(reviewed_at: nil)
    refresh
    assert_equal 25, @event.reload.percent
    review.update!(reviewed_at: Time.current)
    refresh
    assert_equal 26, @event.reload.percent
    review.post_ship_event.update_columns(certification_status: "rejected")
    refresh
    assert_equal 25, @event.reload.percent
  end

  test "repairs at zero do not bank credit against future damage" do
    reviewed_ship(user: @human, minutes: 300_000, at: @cutoff + 1.hour)
    reviewed_ship(user: @buku, minutes: 3000, at: @cutoff + 2.hours)
    refresh
    assert_equal 1, @event.reload.percent
  end

  test "100 percent is not terminal and excess damage is not banked" do
    reviewed_ship(user: @buku, minutes: 6000 * 60, at: @cutoff + 1.hour)
    refresh
    assert_equal 100, @event.reload.percent
    reviewed_ship(user: @human, minutes: 50 * 60, at: @cutoff + 2.hours)
    refresh
    assert_equal 99, @event.reload.percent
  end

  test "late approvals replay in ship order rather than job order" do
    early = reviewed_ship(user: @buku, minutes: 3000, at: @cutoff + 1.hour, reviewed_at: nil)
    reviewed_ship(user: @human, minutes: 1500, at: @cutoff + 2.hours)
    refresh
    assert_equal 24.5, @event.reload.percent
    early.update!(reviewed_at: Time.current)
    refresh
    assert_equal 25.5, @event.reload.percent
  end

  test "no end date and no reset when the flag is temporarily disabled" do
    reviewed_ship(user: @buku, minutes: 3000, at: @cutoff + 1.hour)
    refresh
    Flipper.disable(:bukux3)
    review = reviewed_ship(user: @buku, minutes: 3000, at: @cutoff + 2.hours)
    refresh
    assert_equal 26, @event.reload.percent
    assert_not @event.contributions.exists?(ysws_review: review)
    Flipper.enable(:bukux3)
    travel_to @cutoff + 2.years
    reviewed_ship(user: @human, minutes: 1500, at: Time.current - 1.hour)
    refresh
    assert_equal 26.5, @event.reload.percent
    assert_equal @cutoff, @event.unlocked_at
  end

  test "future-dated ships do not count" do
    reviewed_ship(user: @buku, minutes: 3000, at: Time.current + 1.hour)
    refresh
    assert_empty @event.contributions
  end

  test "saved roles cannot change on a later reconciliation" do
    reviewed_ship(user: @buku, minutes: 3000, at: @cutoff + 1.hour)
    refresh
    BukuX3::Assignment.stub(:buku?, false) { BukuX3::Refresh.call }
    assert @event.contributions.sole.buku?
    assert_equal 26, @event.reload.percent
  end

  private
    def refresh
      BukuX3::Assignment.stub(:buku?, ->(user) { user.id == @buku.id }) { BukuX3::Refresh.call }
    end
end
