require "test_helper"

class Workshop::NotifyRsvpsJobTest < ActiveJob::TestCase
  test "notifies rsvps when the scheduled start time still matches" do
    workshop = workshops(:upcoming)

    assert_difference -> { Notifications::Workshops::StartingSoon.count }, 2 do
      Workshop::NotifyRsvpsJob.perform_now(workshop.id, workshop.starts_at.iso8601)
    end
  end

  test "no-ops when the workshop was rescheduled after this job was enqueued" do
    workshop = workshops(:upcoming)

    assert_no_difference -> { Notification.count } do
      Workshop::NotifyRsvpsJob.perform_now(workshop.id, (workshop.starts_at + 1.day).iso8601)
    end
    assert_nil workshop.reload.rsvps_notified_at
  end

  test "no-ops when the workshop is gone" do
    assert_nothing_raised do
      Workshop::NotifyRsvpsJob.perform_now(-1, Time.current.iso8601)
    end
  end
end
