class CreateStickyStreaks < ActiveRecord::Migration[8.1]
  def change
    create_table :sticky_streaks do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.date :started_on, null: false

      t.timestamps
    end
  end
end
