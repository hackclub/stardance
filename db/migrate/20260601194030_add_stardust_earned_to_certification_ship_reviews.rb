class AddStardustEarnedToCertificationShipReviews < ActiveRecord::Migration[8.1]
  REVIEW_BOUNTY = 1

  def up
    add_column :certification_ship_reviews, :stardust_earned, :integer

    safety_assured do
      execute <<~SQL.squish
        UPDATE certification_ship_reviews
        SET stardust_earned = #{REVIEW_BOUNTY}
        WHERE status != 0
          AND reviewer_id IS NOT NULL
      SQL
    end
  end

  def down
    remove_column :certification_ship_reviews, :stardust_earned
  end
end
