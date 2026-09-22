require "test_helper"

class RocketProgressComponentTest < ViewComponent::TestCase
  test "personal hours occupy the end of the filled total without adding to it" do
    render_progress(hours: 2750, user_hours: 150)

    assert_selector "[role='progressbar'][aria-valuenow='2750']"
    assert_selector ".rocket-progress__contribution-label", text: "You contributed 150 h"
    assert_selector ".rocket-progress__meter[style*='--rocket-progress-fill: 55.0%']"
    assert_selector ".rocket-progress__meter[style*='--rocket-progress-contribution: 5.4545%']"
  end

  test "no contribution segment or label when the user has not contributed" do
    render_progress(hours: 0, user_hours: 0)

    assert_no_selector ".rocket-progress__contribution"
    assert_no_selector ".rocket-progress__contribution-label"
  end

  test "small contributions retain fractional hours and completed goals stay capped" do
    render_progress(hours: 5250, user_hours: 0.1)

    assert_selector "[role='progressbar'][aria-valuenow='5000']"
    assert_selector ".rocket-progress__contribution-label", text: "You contributed 0.1 h"
    assert_selector ".rocket-progress__meter[style*='--rocket-progress-fill: 100%']"
  end

  test "flag still hides the entire component" do
    Flipper.stub(:enabled?, false) do
      render_inline RocketProgressComponent.new(user: users(:one))
      assert_no_selector ".rocket-progress"
    end
  end

  private

    def render_progress(hours:, user_hours:)
      snapshot = RocketProgress::Snapshot.new(hours: hours, goal_hours: 5000, user_hours: user_hours)
      Flipper.stub(:enabled?, true) do
        RocketProgress.stub(:snapshot, snapshot) do
          render_inline RocketProgressComponent.new(user: users(:one))
        end
      end
    end
end
