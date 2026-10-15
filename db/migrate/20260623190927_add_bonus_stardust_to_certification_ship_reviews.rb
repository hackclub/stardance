class AddBonusStardustToCertificationShipReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_ship_reviews, :bonus_stardust, :float
  end
end
