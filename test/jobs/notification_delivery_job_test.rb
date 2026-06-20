require "test_helper"

class NotificationDeliveryJobTest < ActiveJob::TestCase
  setup do
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    @bob   = create_user(slack_id: "U_BOB",   display_name: "bob")
    @notification = Notifications::NewFollower.create!(recipient: @bob, actor: @alice)
  end

  test "slack channel enqueues SendSlackDmJob and stamps slack_enqueued_at" do
    assert_enqueued_with(job: SendSlackDmJob, args: [
      @bob.slack_id,
      "✨ <@#{@alice.slack_id}> just started following you on Stardance!",
      { blocks_path: nil, locals: {} }
    ]) do
      NotificationDeliveryJob.perform_now(@notification.id, "slack")
    end

    assert_not_nil @notification.reload.slack_enqueued_at
  end

  test "slack channel no-ops when recipient has no slack_id" do
    @bob.update!(slack_id: nil)

    assert_no_enqueued_jobs(only: SendSlackDmJob) do
      NotificationDeliveryJob.perform_now(@notification.id, "slack")
    end

    assert_nil @notification.reload.slack_enqueued_at
  end

  test "unknown channel logs and exits cleanly" do
    assert_nothing_raised do
      NotificationDeliveryJob.perform_now(@notification.id, "carrier_pigeon")
    end
  end

  test "missing notification id is a no-op" do
    assert_nothing_raised do
      NotificationDeliveryJob.perform_now(999_999_999, "slack")
    end
  end
end
