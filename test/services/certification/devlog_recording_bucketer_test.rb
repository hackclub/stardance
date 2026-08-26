require "test_helper"

module Certification
  class DevlogRecordingBucketerTest < ActiveSupport::TestCase
    # Two back-to-back day-long windows for devlogs 101 and 202.
    WINDOWS = {
      101 => { since: "2026-06-01T00:00:00Z", before: "2026-06-02T00:00:00Z" },
      202 => { since: "2026-06-02T00:00:00Z", before: "2026-06-03T00:00:00Z" }
    }.freeze

    # A Lapse timelapse hash carries its recording time as epoch milliseconds.
    def lapse(id, recorded_at)
      { id: id, createdAt: (recorded_at.to_i * 1000).to_s }
    end

    # A Lookout recording hash carries its recording time as a Time.
    def lookout(name, recorded_at)
      { name: name, recorded_at: recorded_at }
    end

    test "buckets a lapse under the devlog whose window contains its recording time" do
      tl = lapse("a", Time.utc(2026, 6, 1, 12))

      result = DevlogRecordingBucketer.call(recordings: [ tl ], windows: WINDOWS)

      assert_equal [ tl ], result[101]
      assert_nil result[202]
    end

    test "buckets a lookout recording by its recorded_at time" do
      rec = lookout("desktop", Time.utc(2026, 6, 2, 15))

      result = DevlogRecordingBucketer.call(recordings: [ rec ], windows: WINDOWS)

      assert_equal [ rec ], result[202]
      assert_nil result[101]
    end

    test "buckets lapses and lookout recordings together into their windows" do
      tl  = lapse("tl", Time.utc(2026, 6, 1, 9))
      rec = lookout("web", Time.utc(2026, 6, 1, 18))

      result = DevlogRecordingBucketer.call(recordings: [ tl, rec ], windows: WINDOWS)

      assert_equal [ tl, rec ], result[101]
    end

    test "drops a recording made outside every devlog window" do
      tl = lapse("orphan", Time.utc(2026, 6, 5, 12))

      result = DevlogRecordingBucketer.call(recordings: [ tl ], windows: WINDOWS)

      assert_empty result
    end

    test "splits multiple recordings across the devlogs they contributed to" do
      first  = lapse("first", Time.utc(2026, 6, 1, 9))
      second = lookout("second", Time.utc(2026, 6, 2, 15))

      result = DevlogRecordingBucketer.call(recordings: [ first, second ], windows: WINDOWS)

      assert_equal [ first ], result[101]
      assert_equal [ second ], result[202]
    end

    test "a recording on a window boundary belongs to the later window" do
      # Windows are half-open [since, before): the instant a window ends is the
      # next window's start, so a boundary recording buckets forward, like commits.
      tl = lapse("boundary", Time.utc(2026, 6, 2, 0, 0, 0))

      result = DevlogRecordingBucketer.call(recordings: [ tl ], windows: WINDOWS)

      assert_nil result[101]
      assert_equal [ tl ], result[202]
    end

    test "skips a recording with a blank recording time" do
      result = DevlogRecordingBucketer.call(
        recordings: [ { id: "x", createdAt: nil, recorded_at: nil } ], windows: WINDOWS
      )

      assert_empty result
    end
  end
end
