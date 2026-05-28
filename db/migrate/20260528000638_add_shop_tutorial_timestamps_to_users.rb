class AddShopTutorialTimestampsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :shop_tutorial_started_at, :datetime
    add_column :users, :shop_tutorial_completed_at, :datetime
  end
end
