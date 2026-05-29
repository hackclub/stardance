class RemoveDevlogReviewIdFromPostDevlogs < ActiveRecord::Migration[8.1]
  def change
    # Remove the foreign key first
    remove_foreign_key :post_devlogs, column: :devlog_review_id, if_exists: true

    # Remove the column and its index
    # Column is already ignored in Post::Devlog model (self.ignored_columns)
    safety_assured { remove_column :post_devlogs, :devlog_review_id, :bigint, if_exists: true }
  end
end
