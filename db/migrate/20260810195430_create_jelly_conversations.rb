class CreateJellyConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :jelly_conversations do |t|
      t.string :jelly_id, null: false
      t.string :status, null: false
      t.datetime :opened_at
      t.datetime :last_inbound_at
      t.datetime :last_outbound_at
      t.integer :first_response_seconds
      t.datetime :resolved_at
      t.integer :assignee_count, default: 0, null: false
      t.datetime :remote_updated_at
      t.datetime :messages_synced_at
      t.datetime :synced_at

      t.timestamps
    end
    add_index :jelly_conversations, :jelly_id, unique: true
    add_index :jelly_conversations, :status
    add_index :jelly_conversations, :remote_updated_at
  end
end
