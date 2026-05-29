class CreateYswsReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :certification_ysws_reviews do |t|
      t.references :reviewer, foreign_key: { to_table: :users }, null: false
      t.references :user, foreign_key: true, null: false
      t.references :project, foreign_key: true, null: false
      t.references :ship_cert, foreign_key: { to_table: :post_ship_events }, null: true
      t.references :post_ship_event, foreign_key: { to_table: :post_ship_events }, null: false
      t.references :spotchecked_by, foreign_key: { to_table: :users }, null: true

      t.timestamp :reviewed_at
      t.timestamp :spotchecked_at
      t.timestamp :repo_checked_at
      t.timestamp :demo_checked_at
      t.timestamp :airtable_synced_at

      t.integer :original_minutes
      t.integer :approved_minutes
      t.text :summary_justification

      t.timestamps
    end
  end
end
