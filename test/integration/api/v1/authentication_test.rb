require "test_helper"

module Api
  module V1
    # Exercises the ApiAuthenticatable concern through a representative
    # key-gated endpoint (project posts index).
    class AuthenticationTest < ActionDispatch::IntegrationTest
      include ApiRequestHelpers

      setup do
        @user    = users(:one)
        @project = projects(:one)
        @url     = api_v1_project_posts_url(@project)
      end

      test "missing Authorization header is rejected" do
        get @url

        assert_response :unauthorized
        assert_match(/Authorization header/, json_response["error"])
      end

      test "non-Bearer Authorization scheme is rejected" do
        get @url, headers: { "Authorization" => "Token #{@user.api_key}" }

        assert_response :unauthorized
        assert_match(/Authorization header/, json_response["error"])
      end

      test "Bearer with a blank token is rejected" do
        get @url, headers: { "Authorization" => "Bearer    " }

        assert_response :unauthorized
        assert_equal "Missing API key", json_response["error"]
      end

      test "an unknown api key is rejected" do
        get @url, headers: { "Authorization" => "Bearer not-a-real-key" }

        assert_response :unauthorized
        assert_equal "Invalid API key", json_response["error"]
      end

      test "a valid api key is authorized" do
        get @url, headers: api_headers(@user)

        assert_response :success
      end

      test "authentication errors carry a request_id" do
        get @url

        assert json_response["request_id"].present?, "expected error body to include request_id"
      end
    end
  end
end
