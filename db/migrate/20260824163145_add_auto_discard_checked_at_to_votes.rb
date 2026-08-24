class AddAutoDiscardCheckedAtToVotes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :votes, :auto_discard_checked_at, :datetime

    safety_assured do
      execute <<~SQL.squish
        UPDATE votes
        SET auto_discard_checked_at = created_at
        WHERE auto_discard_checked_at IS NULL
      SQL
    end
  end

  def down
    remove_column :votes, :auto_discard_checked_at
  end
end
