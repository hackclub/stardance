class AddInAppEnabledToUserNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_notification_preferences, :in_app_enabled, :boolean
  end
end
