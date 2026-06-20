class My::NotificationSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_notifications_feature

  def show
    authorize :my, :show_notification_settings?

    @grouped_types = Notifications::Registry.all.group_by(&:category_group)
    @preferences_by_category = current_user.notification_preferences.index_by(&:category)
  end

  def update
    authorize :my, :update_notification_settings?

    submitted = permitted_preferences

    Notifications::Registry.all.each do |klass|
      next if klass.default_priority.to_s == "critical"

      category = klass.category_key.to_s
      data = submitted[category] || {}

      pref = current_user.notification_preferences.find_or_initialize_by(category: category)
      pref.in_app_enabled = parse_bool(data["in_app"])
      pref.slack_enabled = parse_bool(data["slack"])
      pref.email_enabled = parse_bool(data["email"])
      pref.save!
    end

    redirect_to my_notification_settings_path, notice: "Notification preferences saved"
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

  def parse_bool(value)
    case value
    when "1", "true", true then true
    when "0", "false", false then false
    end
  end

  def permitted_preferences
    categories = Notifications::Registry.all.map { |k| k.category_key.to_s }
    nested = categories.index_with { [ :in_app, :slack, :email ] }
    params.fetch(:preferences, {}).permit(nested).to_h
  end
end
