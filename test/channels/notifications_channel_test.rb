require "test_helper"

class NotificationsChannelTest < ActionCable::Channel::TestCase
  setup do
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    stub_connection current_user: @alice
  end

  test "subscribes and streams for the current user" do
    subscribe
    assert subscription.confirmed?
    assert_has_stream_for @alice
  end

  test "rejects subscription when current_user is nil (anonymous connection)" do
    stub_connection current_user: nil
    subscribe
    assert subscription.rejected?
  end

  test "broadcast_unseen_count pushes the unseen count to the user stream" do
    Notifications::NewFollower.create!(recipient: @alice, actor: create_user(slack_id: "U_BOB", display_name: "bob"))

    assert_broadcasts(NotificationsChannel.broadcasting_for(@alice), 1) do
      NotificationsChannel.broadcast_unseen_count(@alice)
    end
  end
end
