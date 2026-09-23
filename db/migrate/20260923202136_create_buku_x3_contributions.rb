class CreateBukuX3Contributions < ActiveRecord::Migration[8.1]
  def change
    create_table :buku_x3_contributions do |t|
      t.references :event, null: false, foreign_key: { to_table: :buku_x3_events, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :ysws_review, null: false, foreign_key: { to_table: :certification_ysws_reviews, on_delete: :cascade }
      t.boolean :buku, null: false
      t.integer :minutes, null: false, default: 0
      t.datetime :shipped_at, null: false

      t.timestamps
    end
    add_index :buku_x3_contributions, [ :event_id, :ysws_review_id ], unique: true
    add_check_constraint :buku_x3_contributions, "minutes >= 0", name: "buku_x3_positive_minutes"
  end
end
