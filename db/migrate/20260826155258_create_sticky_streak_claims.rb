class CreateStickyStreakClaims < ActiveRecord::Migration[8.1]
  def change
    create_table :sticky_streak_claims do |t|
      t.references :sticky_streak, null: false, foreign_key: true
      t.integer :day_number, null: false
      t.references :shop_order, null: false, foreign_key: true, index: { unique: true }

      t.timestamps
    end

    add_index :sticky_streak_claims, [ :sticky_streak_id, :day_number ], unique: true
  end
end
