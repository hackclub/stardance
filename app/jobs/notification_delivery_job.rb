class NotificationDeliveryJob < ApplicationJob
  queue_as :latency_5m

  discard_on ActiveJob::DeserializationError

  def perform(notification_id, channel)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    case channel.to_s
    when "slack" then deliver_slack(notification)
    when "email" then deliver_email(notification)
    else
      Rails.logger.warn("NotificationDeliveryJob: unknown channel #{channel.inspect}")
    end
  end

  private

  def deliver_slack(notification)
    return if notification.slack_enqueued_at.present?

    recipient = notification.recipient
    return unless recipient&.slack_id.present?

    payload = notification.slack_payload
    return if payload[:message].blank? && payload[:blocks_path].blank?

    SendSlackDmJob.perform_later(
      recipient.slack_id,
      payload[:message],
      blocks_path: payload[:blocks_path],
      locals: payload[:locals] || {}
    )

    notification.update_column(:slack_enqueued_at, Time.current)
  end

  def deliver_email(notification)
    return if notification.email_delivered_at.present?

    recipient = notification.recipient
    return unless recipient&.email.present?

    NotificationMailer.notification(notification.id).deliver_now
    notification.update_column(:email_delivered_at, Time.current)
  rescue StandardError => e
    Rails.logger.error("NotificationDeliveryJob email delivery failed (#{notification.id}): #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
