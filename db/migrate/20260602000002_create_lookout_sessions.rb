class CreateLookoutSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :lookout_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :devlog, null: true, foreign_key: { to_table: :post_devlogs }
      t.string :token, null: false
      t.string :status, default: "pending"
      t.string :mode
      t.integer :duration_seconds, default: 0
      t.string :recording_url
      t.datetime :started_at
      t.datetime :stopped_at

      t.timestamps
    end

    add_index :lookout_sessions, :token, unique: true
    add_index :lookout_sessions, [ :project_id, :status ]
  end
end
