class RenameFlavortownMetrics < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :flavortown_message_count_14d, :message_count_14d
    rename_column :users, :flavortown_support_message_count_14d, :support_message_count_14d
  end
end
