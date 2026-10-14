class AddRatingLifecycleToPostShipEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :post_ship_events, :voting_started_at, :datetime, if_not_exists: true
    add_column :post_ship_events, :voting_completed_at, :datetime, if_not_exists: true
    add_column :post_ship_events, :paid_at, :datetime, if_not_exists: true
    add_column :post_ship_events, :lifecycle_data_quality, :string, if_not_exists: true

    add_index :post_ship_events, :voting_started_at, algorithm: :concurrently, if_not_exists: true
    add_index :post_ship_events, :voting_completed_at, algorithm: :concurrently, if_not_exists: true
    add_index :post_ship_events, :paid_at, algorithm: :concurrently, if_not_exists: true
  end
end
