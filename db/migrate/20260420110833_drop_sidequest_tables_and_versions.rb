class DropSidequestTablesAndVersions < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute "DELETE FROM versions WHERE item_type = 'SidequestEntry'"
    end

    safety_assured { drop_table :sidequest_entries }
    safety_assured { drop_table :sidequests }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
