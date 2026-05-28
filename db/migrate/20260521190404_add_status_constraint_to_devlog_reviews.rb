class AddStatusConstraintToDevlogReviews < ActiveRecord::Migration[8.1]
  def change
    # Backfill any NULL statuses to 'pending'
    reversible do |dir|
      dir.up do
        Certification::Devlog.where(status: nil).update_all(status: "pending")
      end
    end

    # Add default
    change_column_default :certification_devlog_reviews, :status, "pending"

    # Add check constraint without validating (non-blocking)
    add_check_constraint :certification_devlog_reviews, "status IS NOT NULL", name: "certification_devlog_reviews_status_null", validate: false
  end
end
