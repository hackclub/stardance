class BroadcastNotificationJob < ApplicationJob
  queue_as :latency_5m

  discard_on ActiveJob::DeserializationError

  def perform(notification_id, aggregated:)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    NotificationsChannel.broadcast_notification(notification, aggregated: aggregated)
  end
end
