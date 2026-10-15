class AddForeignKeyToCertificationYswsReviewsClaimedBy < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :certification_ysws_reviews, :users, column: :claimed_by_id, validate: false
  end
end
