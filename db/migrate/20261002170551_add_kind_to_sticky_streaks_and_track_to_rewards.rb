class AddKindToStickyStreaksAndTrackToRewards < ActiveRecord::Migration[8.1]
  def change
    add_column :sticky_streaks, :kind, :string, null: false, default: "first"
    add_column :sticky_streak_rewards, :track, :string, null: false, default: "standard"
  end
end
