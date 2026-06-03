class CreateDevlogLookoutSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :devlog_lookout_sessions do |t|
      t.references :devlog, null: false, foreign_key: { to_table: :post_devlogs }
      t.references :lookout_session, null: false, foreign_key: true

      t.timestamps
    end

    add_index :devlog_lookout_sessions, [:devlog_id, :lookout_session_id], unique: true, name: "idx_devlog_lookout_sessions_unique"
  end
end
