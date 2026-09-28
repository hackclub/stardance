class NotificationMailer < ApplicationMailer
  def notification(notification_id)
    @notification = Notification.find_by(id: notification_id)
    return if @notification.nil?
    return if @notification.recipient.email.blank?

    @recipient = @notification.recipient
    @actor     = @notification.actor
    @record    = @notification.record

    mail(
      to:            @recipient.email,
      subject:       @notification.email_subject,
      template_name: @notification.template_key
    )
  end
end
