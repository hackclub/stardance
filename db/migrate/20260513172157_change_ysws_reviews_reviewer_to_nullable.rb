class ChangeYswsReviewsReviewerToNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :certification_ysws_reviews, :reviewer_id, true
  end
end
