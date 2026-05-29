class CreateShipReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :ship_reviews do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.references :reviewer, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.text :feedback
      t.text :internal_reason
      t.datetime :claim_expires_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :ship_reviews, :project_id,
              unique: true,
              where: "status = 0",
              name: "index_ship_reviews_unique_pending_project"
    add_index :ship_reviews, [ :status, :claim_expires_at ]
  end
end
