class ValidateForeignKeyOnCertificationYswsReviewsClaimedBy < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :certification_ysws_reviews, :users, column: :claimed_by_id
  end
end
