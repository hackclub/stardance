class CreateDailyRolls < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_rolls do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :value, null: false
      t.date :rolled_on, null: false

      t.timestamps
    end

    add_index :daily_rolls, [ :user_id, :rolled_on ], unique: true
    add_index :daily_rolls, [ :rolled_on, :value ]
  end
end
