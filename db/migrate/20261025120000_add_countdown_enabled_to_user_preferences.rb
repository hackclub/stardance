class AddCountdownEnabledToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :countdown_enabled, :boolean, default: true, null: false
  end
end
