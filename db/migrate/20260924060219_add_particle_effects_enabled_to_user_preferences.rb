class AddParticleEffectsEnabledToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :particle_effects_enabled, :boolean, default: true, null: false
  end
end
