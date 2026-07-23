class AddClaimedByForeignKeyToCertificationIntegrities < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :certification_integrities, :users, column: :claimed_by_id, validate: false
  end
end
