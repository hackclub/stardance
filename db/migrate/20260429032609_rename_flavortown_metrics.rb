class RenameFlavortownMetrics < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      rename_column :users, :flavortown_message_count_14d, :message_count_14d
      rename_column :users, :flavortown_support_message_count_14d, :support_message_count_14d
    end
  end

  def down
    safety_assured do
      rename_column :users, :message_count_14d, :flavortown_message_count_14d
      rename_column :users, :support_message_count_14d, :flavortown_support_message_count_14d
    end
  end
end
