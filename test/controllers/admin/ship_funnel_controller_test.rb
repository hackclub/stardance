require "test_helper"

class Admin::ShipFunnelControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  EMPTY_AIRTABLE = Struct.new(:rows) { def all(**) = rows }.new([])

  setup do
    @admin = create_user(slack_id: "U_SHIP_FUNNEL_ADMIN", display_name: "ship_funnel_admin")
    @admin.grant_role!(:admin)
    @member = create_user(slack_id: "U_SHIP_FUNNEL_MEMBER", display_name: "ship_funnel_member")
    Rails.cache.delete(Admin::ShipFunnelController::CACHE_KEY)
  end

  test "an admin sees the chart and the loops footer" do
    sign_in @admin

    Certification::YswsAirtable.stub(:table, EMPTY_AIRTABLE) { get admin_ship_funnel_path }

    assert_response :success
    assert_select "h1", "Jeremy Funnel"
    assert_select "[data-controller='ship-funnel'] svg[data-ship-funnel-target='chart']"
    assert_select ".ship-funnel__footer", /Loops not pictured/
  end

  test "someone who isn't an admin can't open it" do
    sign_in @member

    get admin_ship_funnel_path

    assert_response :not_found
  end
end
