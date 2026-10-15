require "test_helper"

class ActiveInsightsDisclosureTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test "explains that the dashboard is intentionally public" do
    get "/insights"

    assert_response :success
    assert_select ".insights-disclosure[role=note][data-insights-disclosure]" do
      assert_select ".insights-disclosure__title", text: "This dashboard is intentionally public."
      assert_select ".insights-disclosure__body", text: /not valid security vulnerabilities and waste our team’s time/
      assert_select "button.insights-disclosure__dismiss[type=button][aria-label='Dismiss notice'][data-insights-disclosure-dismiss]", count: 1
    end
  end
end
