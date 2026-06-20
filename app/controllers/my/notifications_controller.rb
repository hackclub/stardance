class My::NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_notifications_feature

  def index
    authorize :my, :show_notifications?

    @body_class = "app-layout-page"

    @pagy, @notifications = pagy(
      Notification.inbox_for(current_user).includes(:actor),
      limit: 25
    )

    Notification.preload_inbox_records!(@notifications)
    @notifications = @notifications.reject(&:orphaned?)

    mark_all_as_read!
  end

  # Live "I'm looking at the inbox" signal from the JS controller when new rows
  # stream in. Seen and read are unified, so this reads them too.
  def mark_all_seen
    authorize :my, :update_notification?
    current_user.notifications.unread.update_all(read_at: Time.current, seen_at: Time.current)
    BroadcastUnseenCountJob.perform_later(current_user.id)
    redirect_back fallback_location: my_notifications_path
  end

  private

  def authenticate_user!
    return if current_user.present?

    store_return_to
    redirect_to root_path, alert: "Please sign in to continue."
  end

  def require_notifications_feature
    redirect_to root_path unless Notification.enabled_for?(current_user)
  end

  # Opening the inbox is the act of reading: seen and read are one state, so a
  # visit marks ALL unread rows read (and seen), not just the loaded page.
  # Otherwise a user with 100 unread and a 25-per-page inbox would walk away
  # with the badge stuck at 75. The rows already loaded above still render with
  # their pre-visit state, so they stay highlighted for this one visit.
  def mark_all_as_read!
    return if request.headers["Purpose"] == "prefetch"

    affected = current_user.notifications.unread.update_all(read_at: Time.current, seen_at: Time.current)
    BroadcastUnseenCountJob.perform_later(current_user.id) if affected.positive?
  end
end
