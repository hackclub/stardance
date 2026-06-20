require "test_helper"

class My::NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:week_2_release)
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    @bob   = create_user(slack_id: "U_BOB",   display_name: "bob")
    sign_in(@alice)
  end

  test "index renders and marks loaded unseen rows as seen" do
    notification = Notifications::NewFollower.notify(recipient: @alice, actor: @bob)

    get my_notifications_path
    assert_response :success

    assert_not_nil notification.reload.seen_at
  end

  test "index hides notifications with destroyed polymorphic record" do
    Notification.create!(
      recipient: @alice,
      type: "Notifications::NewFollower",
      record_type: "Project",
      record_id: 999_999_999,
      params: {}
    )
    visible = Notifications::NewFollower.notify(recipient: @alice, actor: @bob)

    get my_notifications_path
    assert_response :success
    assert_select "li.notifications-item", count: 1
    assert visible.reload.seen_at.present?
  end

  test "mark_all_seen clears unseen across all rows" do
    3.times { Notifications::NewFollower.notify(recipient: @alice, actor: @bob) }

    assert_difference -> { @alice.notifications.unseen.count }, -1 do
      post mark_all_seen_my_notifications_path
    end
  end

  test "logged out users are bounced" do
    delete logout_path
    get my_notifications_path
    assert_response :redirect
  end
end
