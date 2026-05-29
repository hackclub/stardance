class ValidateStatusConstraintOnDevlogReviews < ActiveRecord::Migration[8.1]
  def up
    # Validate the check constraint (can run concurrently, doesn't block)
    validate_check_constraint :certification_devlog_reviews, name: "certification_devlog_reviews_status_null"

    # Now that constraint is validated, add NOT NULL to the column
    change_column_null :certification_devlog_reviews, :status, false

    # Remove the check constraint (no longer needed since column is NOT NULL)
    remove_check_constraint :certification_devlog_reviews, name: "certification_devlog_reviews_status_null"
  end

  def down
    # Re-add the check constraint without validating
    add_check_constraint :certification_devlog_reviews, "status IS NOT NULL", name: "certification_devlog_reviews_status_null", validate: false

    # Allow NULLs again
    change_column_null :certification_devlog_reviews, :status, true
  end
end
