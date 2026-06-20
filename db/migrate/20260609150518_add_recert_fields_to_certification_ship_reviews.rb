class AddRecertFieldsToCertificationShipReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_ship_reviews, :recert_reason, :text
    add_column :certification_ship_reviews, :returned_by_id, :bigint
  end
end
