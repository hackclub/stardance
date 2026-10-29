class ReindexStickyStreakUniqueness < ActiveRecord::Migration[8.1]
  # A user now gets one run of each kind, and a day can pay out once per
  # reward track, so both uniqueness constraints gain a column.
  disable_ddl_transaction!

  def change
    add_index :sticky_streaks, [ :user_id, :kind ], unique: true, algorithm: :concurrently
    remove_index :sticky_streaks, :user_id, unique: true, algorithm: :concurrently

    add_index :sticky_streak_rewards, [ :track, :day_number ], unique: true, algorithm: :concurrently
    remove_index :sticky_streak_rewards, :day_number, unique: true, algorithm: :concurrently
  end
end
