class MyPolicy < ApplicationPolicy
  def show_balance?
    signed_in_any?
  end

  def update_settings?
    signed_in_any?
  end

  def create_dismissal?
    signed_in_any?
  end

  def show_notifications?
    signed_in_any?
  end

  def update_notification?
    signed_in_any?
  end

  def show_notification_settings?
    signed_in_any?
  end

  def update_notification_settings?
    signed_in_any?
  end
end
