class CreatePostViews < ActiveRecord::Migration[8.1]
  def change
    create_table :post_views do |t|
      t.references :post, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.datetime :read_at

      t.timestamps

      t.index [ :post_id, :user_id ], unique: true
    end
  end
end
