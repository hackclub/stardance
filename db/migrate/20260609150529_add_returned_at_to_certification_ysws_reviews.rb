class AddReturnedAtToCertificationYswsReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_ysws_reviews, :returned_at, :datetime
  end
end
