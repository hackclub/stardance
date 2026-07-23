class ValidateClaimedByForeignKeyOnCertificationIntegrities < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :certification_integrities, :users, column: :claimed_by_id
  end
end
