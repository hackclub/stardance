class CreateDevlogReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :certification_devlog_reviews do |t|
      t.references :post_devlog, foreign_key: { to_table: :post_devlogs }, null: false
      t.references :ysws_review, foreign_key: { to_table: :certification_ysws_reviews }, null: false

      t.integer :original_minutes
      t.integer :approved_minutes
      t.text :justification

      t.timestamps
    end
  end
end
