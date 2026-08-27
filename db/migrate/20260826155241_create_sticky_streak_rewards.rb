class CreateStickyStreakRewards < ActiveRecord::Migration[8.1]
  def change
    create_table :sticky_streak_rewards do |t|
      t.integer :day_number, null: false, index: { unique: true }
      t.references :shop_item, null: false, foreign_key: true

      t.timestamps
    end
  end
end
