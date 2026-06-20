class CreateUserNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :user_notification_preferences do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :category, null: false
      t.boolean :slack_enabled
      t.boolean :email_enabled

      t.timestamps
    end

    add_index :user_notification_preferences, [ :user_id, :category ], unique: true
  end
end
