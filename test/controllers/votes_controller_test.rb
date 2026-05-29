require "test_helper"

class VotesControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_rate_url
    assert_response :success
  end
end
