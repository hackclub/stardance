require "test_helper"

# == Schema Information
#
# Table name: workshops
#
#  id                :bigint           not null, primary key
#  description       :text
#  ends_at           :datetime         not null
#  rsvps_notified_at :datetime
#  starts_at         :datetime         not null
#  title             :string           not null
#  zoom_link         :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_workshops_on_starts_at  (starts_at)
#
class WorkshopTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "fixtures are valid" do
    assert workshops(:upcoming).valid?
    assert workshops(:joinable).valid?
  end

  test "requires ends_at after starts_at" do
    workshop = workshops(:upcoming)
    workshop.ends_at = workshop.starts_at - 1.minute

    assert_not workshop.valid?
    assert_includes workshop.errors[:ends_at], "must be after the start time"
  end

  test "zoom link is optional but must be https when present" do
    workshop = workshops(:upcoming)

    workshop.zoom_link = nil
    assert workshop.valid?

    workshop.zoom_link = "http://zoom.us/j/123"
    assert_not workshop.valid?

    workshop.zoom_link = "https://zoom.us/j/123"
    assert workshop.valid?
  end

  test "joinable? opens 15 minutes before start and closes at the end" do
    workshop = workshops(:upcoming)

    assert_not workshop.joinable?(workshop.starts_at - 16.minutes)
    assert workshop.joinable?(workshop.starts_at - 15.minutes)
    assert workshop.joinable?(workshop.starts_at + 30.minutes)
    assert workshop.joinable?(workshop.ends_at)
    assert_not workshop.joinable?(workshop.ends_at + 1.second)
  end

  test "state transitions across the join window and start/end boundaries" do
    workshop = workshops(:upcoming)

    assert_equal :upcoming, workshop.state(workshop.starts_at - 16.minutes)
    assert_equal :soon, workshop.state(workshop.starts_at - 15.minutes)
    assert_equal :live, workshop.state(workshop.starts_at)
    assert_equal :live, workshop.state(workshop.ends_at)
    assert_equal :ended, workshop.state(workshop.ends_at + 1.second)
  end

  test "notify_rsvps! notifies every rsvp once" do
    workshop = workshops(:upcoming)

    assert_difference -> { Notifications::Workshops::StartingSoon.count }, 2 do
      workshop.notify_rsvps!
    end
    assert workshop.reload.rsvps_notified_at.present?

    assert_no_difference -> { Notifications::Workshops::StartingSoon.count } do
      workshop.notify_rsvps!
    end
  end

  test "notify_rsvps! is a no-op after the workshop ended" do
    assert_no_difference -> { Notification.count } do
      workshops(:ended).notify_rsvps!
    end
    assert_nil workshops(:ended).reload.rsvps_notified_at
  end

  test "creating a workshop schedules the rsvp notification job" do
    starts_at = 3.days.from_now.change(usec: 0)

    assert_enqueued_with(job: Workshop::NotifyRsvpsJob) do
      Workshop.create!(
        title: "New workshop",
        zoom_link: "https://zoom.us/j/1",
        starts_at: starts_at,
        ends_at: starts_at + 1.hour
      )
    end
  end

  test "moving an announced workshop to a future slot clears the stamp and reschedules" do
    workshop = workshops(:upcoming)
    workshop.update_column(:rsvps_notified_at, Time.current)

    assert_enqueued_with(job: Workshop::NotifyRsvpsJob) do
      workshop.update!(starts_at: 5.days.from_now, ends_at: 5.days.from_now + 1.hour)
    end

    assert_nil workshop.reload.rsvps_notified_at
  end
end
