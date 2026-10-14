class AddReversedAtToHardwareReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_funding_requests, :reversed_at, :datetime
    add_column :certification_ship_reviews, :reversed_at, :datetime
  end
end
