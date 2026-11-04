class AllowUndonePermanentRejectionNominations < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :certification_permanent_rejection_nominations,
      "status IN (0, 1, 2)", name: "permanent_rejection_status"
    add_check_constraint :certification_permanent_rejection_nominations,
      "status IN (0, 1, 2, 3)", name: "permanent_rejection_status", validate: false
  end
end
