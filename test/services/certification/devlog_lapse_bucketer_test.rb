require "test_helper"

module Certification
  class DevlogLapseBucketerTest < ActiveSupport::TestCase
    # Two back-to-back day-long windows for devlogs 101 and 202.
    WINDOWS = {
      101 => { since: "2026-06-01T00:00:00Z", before: "2026-06-02T00:00:00Z" },
      202 => { since: "2026-06-02T00:00:00Z", before: "2026-06-03T00:00:00Z" }
    }.freeze

    # A Lapse timelapse hash carries its recording time as epoch milliseconds.
    def lapse(id, recorded_at)
      { id: id, createdAt: (recorded_at.to_i * 1000).to_s }
    end

    test "buckets a lapse under the devlog whose window contains its recording time" do
      tl = lapse("a", Time.utc(2026, 6, 1, 12))

      result = DevlogLapseBucketer.call(timelapses: [ tl ], windows: WINDOWS)

      assert_equal [ tl ], result[101]
      assert_nil result[202]
    end

    test "drops a lapse recorded outside every devlog window" do
      tl = lapse("orphan", Time.utc(2026, 6, 5, 12))

      result = DevlogLapseBucketer.call(timelapses: [ tl ], windows: WINDOWS)

      assert_empty result
    end

    test "splits multiple lapses across the devlogs they contributed to" do
      first  = lapse("first", Time.utc(2026, 6, 1, 9))
      second = lapse("second", Time.utc(2026, 6, 2, 15))

      result = DevlogLapseBucketer.call(timelapses: [ first, second ], windows: WINDOWS)

      assert_equal [ first ], result[101]
      assert_equal [ second ], result[202]
    end

    test "a lapse on a window boundary belongs to the later window" do
      # Windows are half-open [since, before): the instant a window ends is the
      # next window's start, so a boundary lapse buckets forward, like commits.
      tl = lapse("boundary", Time.utc(2026, 6, 2, 0, 0, 0))

      result = DevlogLapseBucketer.call(timelapses: [ tl ], windows: WINDOWS)

      assert_nil result[101]
      assert_equal [ tl ], result[202]
    end

    test "skips a lapse with a blank recording time" do
      result = DevlogLapseBucketer.call(timelapses: [ { id: "x", createdAt: nil } ], windows: WINDOWS)

      assert_empty result
    end
  end
end
