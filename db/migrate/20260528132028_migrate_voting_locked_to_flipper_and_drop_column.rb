class MigrateVotingLockedToFlipperAndDropColumn < ActiveRecord::Migration[8.1]
  def up
    safety_assured { remove_column :users, :voting_locked }
  end

  def down
    add_column :users, :voting_locked, :boolean, default: false, null: false
  end
end
