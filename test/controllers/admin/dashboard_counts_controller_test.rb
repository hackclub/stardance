require "test_helper"

class Admin::DashboardCountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(slack_id: "U_DC_ADMIN", display_name: "dc_admin", email: "dc_admin@example.test")
    @admin.grant_role!(:admin)
    @builder = User.create!(slack_id: "U_DC_BUILDER", display_name: "dc_builder", email: "dc_builder@example.test")
    @project = Project.create!(title: "Badge Test Project")
    @project.memberships.create!(user: @builder, role: :owner)
  end

  test "mission reviews badge counts pending software submissions only" do
    ship_to_mission!(@project, @builder, create_mission, status: "pending")

    hardware_mission = create_mission
    hardware_mission.update!(hardware: true)
    ship_to_mission!(@project, @builder, hardware_mission, status: "pending")

    sign_in @admin
    get admin_dashboard_count_path("mission_reviews")

    assert_response :success
    assert_select ".admin-dashboard__count-pill", text: "1"
  end
end
