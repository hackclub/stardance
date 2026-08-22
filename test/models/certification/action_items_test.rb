require "test_helper"

class Certification::ActionItemsTest < ActiveSupport::TestCase
  test "reads the reviewer's dashed lines as action items" do
    review = build("nice work!\n- add a BOM\n- fix tolerances")

    assert_equal [ "add a BOM", "fix tolerances" ], review.action_items
    assert_equal "nice work!", review.feedback_prose
  end

  test "does not treat ordinary prose as an action item" do
    [
      "-5V on the rail is noisy",
      "the range is 3-5 volts",
      "check the readme - it needs an image",
      "---",
      "-",
      "* star bullet"
    ].each do |line|
      assert_empty build(line).action_items, "expected no items for #{line.inspect}"
    end
  end

  private

  def build(feedback)
    Certification::FundingRequest.new(feedback: feedback)
  end
end
