require "test_helper"

class LandingControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get root_url
    assert_response :success
  end

  test "landing page has no disintegration or finale video" do
    get root_url
    assert_select ".blackhole, .stardance-finale", count: 0
  end
end
