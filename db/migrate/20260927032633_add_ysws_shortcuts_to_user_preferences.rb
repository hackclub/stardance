class AddYswsShortcutsToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :ysws_shortcuts, :jsonb, default: {}, null: false
  end
end
