require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  setup do
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    @bob   = create_user(slack_id: "U_BOB",   display_name: "bob")
  end

  test "renders new follower email" do
    notification = Notifications::NewFollower.create!(recipient: @bob, actor: @alice)
    mail = NotificationMailer.notification(notification.id)

    assert_equal [ @bob.email ], mail.to
    assert_equal "@alice started following you on Stardance", mail.subject
    assert_match "@alice", mail.body.encoded
  end

  test "no-ops when recipient has no email" do
    @bob.update!(email: nil)
    notification = Notifications::NewFollower.create!(recipient: @bob, actor: @alice)
    mail = NotificationMailer.notification(notification.id)

    assert_nil mail.message_id
  end

  test "no-ops when notification missing" do
    mail = NotificationMailer.notification(999_999_999)
    assert_nil mail.message_id
  end
end
