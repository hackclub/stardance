class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :recipient, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :record_type
      t.bigint :record_id
      t.string :type, null: false
      t.integer :priority, null: false, default: 0
      t.jsonb :params, null: false, default: {}
      t.string :group_key
      t.integer :group_count, null: false, default: 1
      t.datetime :seen_at
      t.datetime :read_at
      t.datetime :slack_delivered_at
      t.datetime :email_delivered_at

      t.timestamps
    end

    add_index :notifications, [ :recipient_id, :seen_at ]
    add_index :notifications, [ :recipient_id, :created_at ]
    add_index :notifications, [ :recipient_id, :group_key, :read_at ], where: "group_key IS NOT NULL"
    add_index :notifications, [ :record_type, :record_id ]
    add_index :notifications, [ :type, :created_at ]
  end
end
