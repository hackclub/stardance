class AddPlatformAdsEnabledToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :platform_ads_enabled, :boolean, default: true, null: false
  end
end
