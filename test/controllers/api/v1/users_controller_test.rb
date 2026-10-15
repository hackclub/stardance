require "test_helper"

class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  API_FLAG = :"public_api_2026-08-28"

  setup do
    @admin = User.create!(slack_id: "U_API_LOOKUP_ADMIN", display_name: "lookup_admin", email: "lookup_admin@example.test", verification_status: "verified")
    @admin.grant_role!(:admin)
    @admin.regenerate_api_key
    Flipper.enable(API_FLAG, @admin)
  end

  teardown do
    Flipper.disable(API_FLAG, @admin)
  end

  test "lookup returns the user for a slack id" do
    get lookup_api_v1_users_path(slack_id: @admin.slack_id), headers: auth_headers

    assert_response :success
    assert_equal({ "id" => @admin.id, "slack_id" => "U_API_LOOKUP_ADMIN", "display_name" => "lookup_admin" }, response.parsed_body)
  end

  test "lookup requires a slack id" do
    get lookup_api_v1_users_path, headers: auth_headers

    assert_response :bad_request
  end

  test "lookup returns not found for an unknown slack id" do
    get lookup_api_v1_users_path(slack_id: "U_NOPE"), headers: auth_headers

    assert_response :not_found
  end

  test "lookup is forbidden for non-admins" do
    other = User.create!(slack_id: "U_API_LOOKUP_USER", display_name: "plain", email: "plain@example.test", verification_status: "verified")
    other.regenerate_api_key
    Flipper.enable(API_FLAG, other)

    get lookup_api_v1_users_path(slack_id: @admin.slack_id), headers: { "Authorization" => "Bearer #{other.api_key}" }

    assert_response :forbidden
  ensure
    Flipper.disable(API_FLAG, other) if other
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@admin.api_key}" }
  end
end
