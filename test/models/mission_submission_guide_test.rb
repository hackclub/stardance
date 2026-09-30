require "test_helper"

# submission_guide is free-text markdown the mission author types into a
# single textarea; these pin how it's partitioned into the intro paragraph,
# dash-bulleted criteria, and optional outro that the submission requirements
# card renders separately.
class MissionSubmissionGuideTest < ActiveSupport::TestCase
  def mission(submission_guide:)
    Mission.create!(
      slug: "guide-parse-test-#{SecureRandom.hex(4)}",
      name: "Guide parse test",
      description: "Description",
      submission_guide: submission_guide
    )
  end

  test "splits a plain bulleted list into criteria with no intro or outro" do
    m = mission(submission_guide: "- one\n- two\n- three")

    assert_nil m.submission_guide_intro
    assert_equal [ "one", "two", "three" ], m.submission_criteria
    assert_nil m.submission_guide_outro
  end

  test "captures an intro paragraph before the first bullet" do
    m = mission(submission_guide: "Read this first.\n\n- one\n- two")

    assert_equal "Read this first.", m.submission_guide_intro
    assert_equal [ "one", "two" ], m.submission_criteria
  end

  test "captures a trailing outro after the last bullet" do
    m = mission(submission_guide: "- one\n- two\n\nThanks for reading!")

    assert_equal [ "one", "two" ], m.submission_criteria
    assert_equal "Thanks for reading!", m.submission_guide_outro
  end

  test "folds a wrapped continuation line back into the bullet above it, not into the outro" do
    guide = <<~GUIDE
      - must work on desktop! either on windows, mac,
      or linux
      - uploaded to itch.io!
      - time spent on art can count for up to 25% of your
      approved time
    GUIDE
    m = mission(submission_guide: guide)

    assert_equal [
      "must work on desktop! either on windows, mac, or linux",
      "uploaded to itch.io!",
      "time spent on art can count for up to 25% of your approved time"
    ], m.submission_criteria
    assert_nil m.submission_guide_outro
  end

  test "blank guide has no intro, criteria, or outro" do
    m = mission(submission_guide: "")

    assert_nil m.submission_guide_intro
    assert_equal [], m.submission_criteria
    assert_nil m.submission_guide_outro
  end
end
