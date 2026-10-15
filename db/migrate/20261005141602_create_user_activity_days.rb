class CreateUserActivityDays < ActiveRecord::Migration[8.1]
  def change
    create_table :user_activity_days do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :active_on, null: false
      t.string :sources, array: true, null: false, default: []

      t.timestamps
    end

    add_index :user_activity_days, [ :user_id, :active_on ], unique: true
    add_index :user_activity_days, :active_on
  end
end
