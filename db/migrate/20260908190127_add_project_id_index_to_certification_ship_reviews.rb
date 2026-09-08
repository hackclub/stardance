class AddProjectIdIndexToCertificationShipReviews < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :certification_ship_reviews, :project_id,
              algorithm: :concurrently,
              if_not_exists: true
  end
end
