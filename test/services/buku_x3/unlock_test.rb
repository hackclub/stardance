require "test_helper"

class BukuX3UnlockTest < ActiveSupport::TestCase
  include BukuX3Ships

  setup do
    Flipper.disable(:bukux2)
    Flipper.disable(:bukux3)
    @user = users(:one)
    @ship_time = RocketProgress::WINDOW_START + 1.day
    travel_to @ship_time + 1.day
  end

  teardown do
    Flipper.disable(:bukux2)
    Flipper.disable(:bukux3)
    travel_back
  end

  test "bukux2 alone never starts bukux3 even at 5000 hours" do
    reviewed_ship(user: @user, minutes: 300_000, at: @ship_time)
    Flipper.enable(:bukux2)
    assert_nil BukuX3::Unlock.call
    assert_nil BukuX3::Event.current
  end

  test "saved cutoff is permanent across corrections and flag toggles" do
    review = reviewed_ship(user: @user, minutes: 300_000, at: @ship_time)
    Flipper.enable(:bukux3)
    event = BukuX3::Unlock.call
    cutoff = event.unlocked_at
    travel 1.hour
    review.devlog_reviews.sole.update!(approved_minutes: 60)
    Flipper.disable(:bukux3)
    assert_nil BukuX3::Unlock.call
    Flipper.enable(:bukux3)
    assert_equal cutoff, BukuX3::Unlock.call.unlocked_at
    assert_equal cutoff, event.reload.unlocked_at
    assert event.active?
  end

  test "flag alone starts the event below the old goal but excludes earlier ships" do
    reviewed_ship(user: @user, minutes: 3000, at: @ship_time)
    Flipper.enable(:bukux3)
    assert_equal Time.current, BukuX3::Refresh.call.unlocked_at
    assert_equal 0, BukuX3::Contribution.count
    assert_equal 25, BukuX3::Event.percent
  end

  test "an existing milestone is preserved rather than replaced by flag activation" do
    event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.day.ago)
    Flipper.enable(:bukux3)
    assert_equal 1.day.ago, BukuX3::Unlock.call.unlocked_at
    assert_equal event.id, BukuX3::Event.current.id
  end

  test "when initially installed after the goal the cutoff is now, never a guessed historical date" do
    reviewed_ship(user: @user, minutes: 300_000, at: @ship_time)
    Flipper.enable(:bukux3)
    event = BukuX3::Refresh.call
    assert_equal Time.current, event.unlocked_at
    assert_empty event.contributions
  end

  test "disabled events do not create a milestone" do
    reviewed_ship(user: @user, minutes: 300_000, at: @ship_time)
    assert_nil BukuX3::Unlock.call
    assert_nil BukuX3::Event.current
  end

  test "an existing locked event is unlocked without creating a duplicate" do
    event = BukuX3::Event.create!(key: BukuX3::Event::KEY)
    reviewed_ship(user: @user, minutes: 300_000, at: @ship_time)
    Flipper.enable(:bukux3)
    assert_equal event.id, BukuX3::Unlock.call.id
    assert_equal Time.current, event.reload.unlocked_at
    assert_equal 1, BukuX3::Event.count
  end

  test "atomic event creation reuses an existing event" do
    first = BukuX3::Event.create_or_find_by!(key: BukuX3::Event::KEY)
    second = BukuX3::Event.create_or_find_by!(key: BukuX3::Event::KEY)
    assert_equal first.id, second.id
  end
end
