class AddPayoutMultiplierToCertificationShipReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_ship_reviews, :payout_multiplier, :float
  end
end
