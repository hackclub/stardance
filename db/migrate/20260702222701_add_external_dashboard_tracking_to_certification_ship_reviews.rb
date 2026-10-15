class AddExternalDashboardTrackingToCertificationShipReviews < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :certification_ship_reviews, :external_certification_id, :string
    add_column :certification_ship_reviews, :proof_video_url, :string
    add_index :certification_ship_reviews, :external_certification_id, unique: true, algorithm: :concurrently
    add_reference :certification_ship_reviews, :post_ship_event, index: { algorithm: :concurrently }
    add_foreign_key :certification_ship_reviews, :post_ship_events, column: :post_ship_event_id, on_delete: :nullify, validate: false
    validate_foreign_key :certification_ship_reviews, :post_ship_events
  end
end
