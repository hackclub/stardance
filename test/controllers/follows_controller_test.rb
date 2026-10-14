require "test_helper"

class FollowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    @bob   = create_user(slack_id: "U_BOB",   display_name: "bob")
  end

  test "POST create follows the target user" do
    sign_in @alice
    assert_difference "Follow.count", 1 do
      post user_follow_path(@bob)
    end
    assert @alice.follows?(@bob)
  end

  test "DELETE destroy unfollows the target user" do
    Follow.create!(follower: @alice, followed: @bob)
    sign_in @alice
    assert_difference "Follow.count", -1 do
      delete user_follow_path(@bob)
    end
  end

  test "rejects self-follow via policy" do
    sign_in @alice
    assert_no_difference "Follow.count" do
      post user_follow_path(@alice)
    end
    assert_response :forbidden
  end

  test "rejects logged-out users via policy" do
    post user_follow_path(@bob)
    assert_response :forbidden
  end

  test "prompts guest users to upgrade with a forbidden turbo stream response" do
    guest = create_user(slack_id: "U_GUEST", display_name: "guest", hca_linked: false)
    sign_in guest

    assert_no_difference "Follow.count" do
      post user_follow_path(@bob), headers: { "ACCEPT" => Mime[:turbo_stream].to_s }
    end

    assert_response :forbidden
    assert_select "turbo-stream[action='append'][targets='body']", 1 do
      assert_select "dialog.upgrade-modal[aria-labelledby='upgrade-modal-title'][data-turbo-temporary]", 1
      assert_select "#upgrade-modal-title", text: "Sign in to continue"
    end
  end
end
