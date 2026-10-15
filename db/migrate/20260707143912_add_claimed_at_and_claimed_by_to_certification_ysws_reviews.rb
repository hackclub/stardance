class AddClaimedAtAndClaimedByToCertificationYswsReviews < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :certification_ysws_reviews, :claimed_at, :datetime
    add_reference :certification_ysws_reviews, :claimed_by, null: true, foreign_key: false, index: { algorithm: :concurrently }
  end
end
