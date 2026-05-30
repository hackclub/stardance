class AddInUnifiedDbToCertificationYswsReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_ysws_reviews, :in_unified_db, :boolean, default: false, null: false
  end
end
