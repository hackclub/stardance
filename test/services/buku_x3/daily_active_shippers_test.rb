require "test_helper"

class BukuX3DailyActiveShippersTest < ActiveSupport::TestCase
  include BukuX3Ships

  setup do
    travel_to Time.utc(2026, 11, 3, 18)
    @event = BukuX3::Event.create!(key: BukuX3::Event::KEY, unlocked_at: 1.month.ago)
  end

  teardown { travel_back }

  test "counts unique positive contributors per team on eastern ship dates including DST" do
    # Both repeated 1:30 AM hours belong to Nov 1; multiple ships count once.
    contribute(users(:one), true, Time.utc(2026, 11, 1, 5, 30))
    contribute(users(:one), true, Time.utc(2026, 11, 1, 6, 30))
    contribute(users(:two), false, Time.utc(2026, 11, 2, 4, 59))
    contribute(users(:one), true, Time.utc(2026, 11, 2, 5))
    contribute(users(:three), true, Time.utc(2026, 11, 2, 6), minutes: 0)
    rows = @event.daily_active_shippers
    assert_equal 14, rows.length
    assert_equal({ date: Date.new(2026, 11, 3), buku: 0, bean: 0 }, rows.first)
    assert_equal({ date: Date.new(2026, 11, 2), buku: 1, bean: 0 }, rows[1])
    assert_equal({ date: Date.new(2026, 11, 1), buku: 1, bean: 1 }, rows[2])
    assert_equal Date.new(2026, 10, 21), rows.last[:date]
  end

  test "unstarted event has zero filled days without saving a record" do
    assert_no_difference "BukuX3::Event.count" do
      rows = BukuX3::Event.new.daily_active_shippers
      assert_equal 14, rows.length
      assert rows.all? { |row| row[:buku].zero? && row[:bean].zero? }
    end
  end

  test "corrections remove shippers and old or other event contributions are excluded" do
    current = contribute(users(:one), true, 2.hours.ago)
    contribute(users(:one), true, 30.days.ago)
    other = BukuX3::Event.create!(key: "other")
    contribute(users(:two), false, 1.hour.ago, event: other)
    assert_equal 1, @event.daily_active_shippers.sum { |row| row[:buku] }
    assert_equal 0, @event.daily_active_shippers.sum { |row| row[:bean] }
    current.update!(minutes: 0)
    assert_equal 0, @event.daily_active_shippers.sum { |row| row[:buku] }
  end

  private

  def contribute(user, buku, at, minutes: 60, event: @event)
    review = reviewed_ship(user: user, minutes: 60, at: at, reviewed_at: Time.current)
    event.contributions.create!(user: user, buku: buku, shipped_at: at, minutes: minutes, ysws_review: review)
  end
end
