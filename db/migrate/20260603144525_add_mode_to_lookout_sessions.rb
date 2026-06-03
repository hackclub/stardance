class AddModeToLookoutSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :lookout_sessions, :mode, :string
  end
end
