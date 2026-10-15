class CreateJellyDailyStats < ActiveRecord::Migration[8.1]
  def change
    create_table :jelly_daily_stats do |t|
      t.date :recorded_on, null: false
      t.integer :open_count
      t.integer :awaiting_reply_count
      t.integer :arrivals
      t.integer :resolutions
      t.integer :median_first_response_seconds
      t.integer :p95_hang_seconds

      t.timestamps
    end
    add_index :jelly_daily_stats, :recorded_on, unique: true
  end
end
