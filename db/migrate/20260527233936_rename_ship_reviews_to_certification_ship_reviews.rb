class RenameShipReviewsToCertificationShipReviews < ActiveRecord::Migration[8.1]
  def change
    # I'm safety_assured on this b/c the original pr never got merged, so these
    # haven't been applied yet
    safety_assured { rename_table :ship_reviews, :certification_ship_reviews }
  end
end
