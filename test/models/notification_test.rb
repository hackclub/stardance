# == Schema Information
#
# Table name: notifications
#
#  id                 :bigint           not null, primary key
#  email_delivered_at :datetime
#  group_count        :integer          default(1), not null
#  group_key          :string
#  params             :jsonb            not null
#  priority           :integer          default(NULL), not null
#  read_at            :datetime
#  record_type        :string
#  seen_at            :datetime
#  slack_enqueued_at  :datetime
#  type               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  actor_id           :bigint
#  recipient_id       :bigint           not null
#  record_id          :bigint
#
# Indexes
#
#  index_notifications_on_actor_id                                (actor_id)
#  index_notifications_on_recipient_id                            (recipient_id)
#  index_notifications_on_recipient_id_and_created_at             (recipient_id,created_at)
#  index_notifications_on_recipient_id_and_group_key_and_read_at  (recipient_id,group_key,read_at) WHERE (group_key IS NOT NULL)
#  index_notifications_on_recipient_id_and_seen_at                (recipient_id,seen_at)
#  index_notifications_on_record_type_and_record_id               (record_type,record_id)
#  index_notifications_on_type_and_created_at                     (type,created_at)
#  index_notifications_unique_unread_aggregate                    (recipient_id,type,group_key) UNIQUE WHERE ((read_at IS NULL) AND (group_key IS NOT NULL))
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id) ON DELETE => nullify
#  fk_rails_...  (recipient_id => users.id) ON DELETE => cascade
#
require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Flipper.enable(:week_2_release)
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    @bob   = create_user(slack_id: "U_BOB",   display_name: "bob")
    @carol = create_user(slack_id: "U_CAROL", display_name: "carol")
  end

  test "notify inserts a notification row for the recipient" do
    assert_difference "Notification.count", 1 do
      Notifications::NewFollower.notify(recipient: @bob, actor: @alice)
    end

    notification = @bob.notifications.last
    assert_equal "Notifications::NewFollower", notification.type
    assert_equal @alice, notification.actor
    assert_equal "low", notification.priority
  end

  test "notify is a no-op when the week_2_release flag is off for the recipient" do
    Flipper.disable(:week_2_release)

    assert_no_difference "Notification.count" do
      assert_nil Notifications::NewFollower.notify(recipient: @bob, actor: @alice)
    end
  end

  test "notify skips self-notify by default" do
    assert_no_difference "Notification.count" do
      Notifications::NewFollower.notify(recipient: @alice, actor: @alice)
    end
  end

  test "notify aggregates into existing unread row with matching group_key" do
    Notifications::NewFollower.notify(recipient: @bob, actor: @alice)

    assert_no_difference "Notification.count" do
      Notifications::NewFollower.notify(recipient: @bob, actor: @carol)
    end

    notification = @bob.notifications.last
    assert_equal 2, notification.group_count
    assert_equal @carol, notification.actor
  end

  test "notify starts a fresh row once the previous one is read" do
    first = Notifications::NewFollower.notify(recipient: @bob, actor: @alice)
    first.update!(read_at: Time.current)

    assert_difference "Notification.count", 1 do
      Notifications::NewFollower.notify(recipient: @bob, actor: @carol)
    end
  end

  test "low priority enqueues no delivery jobs by default" do
    assert_no_enqueued_jobs(only: NotificationDeliveryJob) do
      Notifications::NewFollower.notify(recipient: @bob, actor: @alice)
    end
  end

  test "orphaned? returns true when the polymorphic record is missing" do
    orphan = notifications(:orphaned_notification)
    assert orphan.orphaned?
  end

  test "aggregation re-surfaces seen rows by clearing seen_at and read_at" do
    first = Notifications::NewFollower.notify(recipient: @bob, actor: @alice)
    first.update!(seen_at: Time.current)
    assert_not_nil first.reload.seen_at

    Notifications::NewFollower.notify(recipient: @bob, actor: @carol)
    assert_nil first.reload.seen_at
    assert_nil first.reload.read_at
  end
end
