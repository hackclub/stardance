class AddDisintegrationEffectsEnabledToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :disintegration_effects_enabled, :boolean, default: true, null: false
  end
end
