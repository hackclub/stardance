require "test_helper"

class Api::V1::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @reader = User.create!(slack_id: "U_API_PROJECTS", display_name: "api_projects", email: "api_projects@example.test", verification_status: "verified")
    @reader.regenerate_api_key
    @owner = User.create!(slack_id: "U_API_MOVER", display_name: "mover", email: "mover@example.test", bio: "I build rovers")
    @project = Project.create!(title: "Rover", description: "A tiny rover", hardware_stage: "design")
  end

  test "a project that hasn't moved to Fabricate says so" do
    get api_v1_project_path(@project), headers: auth_headers

    assert_response :success
    assert_nil response.parsed_body["fabricate_transfer"]
  end

  test "a moved project names the owner Fabricate imports it for" do
    transfer = @project.create_fabricate_transfer!(user: @owner)

    get api_v1_project_path(@project), headers: auth_headers

    assert_equal(
      { "moved_at" => transfer.created_at.as_json, "owner" => { "id" => @owner.id, "slack_id" => "U_API_MOVER", "display_name" => "mover", "bio" => "I build rovers" } },
      response.parsed_body["fabricate_transfer"]
    )
  end

  private
    def auth_headers
      { "Authorization" => "Bearer #{@reader.api_key}" }
    end
end
