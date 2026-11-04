class ValidateUndonePermanentRejectionNominations < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :certification_permanent_rejection_nominations, name: "permanent_rejection_status"
  end
end
