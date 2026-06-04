require "test_helper"

module Api
  module V1
    class UsersTest < ActionDispatch::IntegrationTest
      include ApiRequestHelpers

      PRIVATE_FIELDS = %w[first_name last_name shop_region balance].freeze

      setup do
        @user  = users(:one)
        @other = users(:two)
      end

      test "viewing another user omits private fields" do
        get api_v1_user_url(@other), headers: api_headers(@user)

        assert_response :success
        body = json_response
        assert_equal @other.id, body["id"]
        assert body.key?("display_name")
        PRIVATE_FIELDS.each do |field|
          assert_not body.key?(field), "expected #{field} to be hidden when viewing another user"
        end
      end

      test "the key owner sees their own private fields on /users/me" do
        get api_v1_me_url, headers: api_headers(@user)

        assert_response :success
        body = json_response
        PRIVATE_FIELDS.each do |field|
          assert body.key?(field), "expected #{field} on the owner's own profile"
        end
      end
    end
  end
end
