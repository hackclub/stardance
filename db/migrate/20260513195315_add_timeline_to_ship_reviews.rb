class AddTimelineToShipReviews < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :ship_reviews, :claimed_at, :datetime
    add_column :ship_reviews, :decided_at, :datetime
    add_index :ship_reviews, :decided_at, algorithm: :concurrently
  end
end
