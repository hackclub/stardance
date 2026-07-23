class Workshop::NotifyRsvpsJob < ApplicationJob
  queue_as :latency_5m

  def perform(workshop_id, scheduled_starts_at)
    workshop = Workshop.find_by(id: workshop_id)
    return unless workshop
    # A reschedule enqueued a fresh job for the new start time; this one is stale.
    return unless workshop.starts_at.iso8601 == scheduled_starts_at

    workshop.notify_rsvps!
  end
end
