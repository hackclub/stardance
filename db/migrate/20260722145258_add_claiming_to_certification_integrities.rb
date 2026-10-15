class AddClaimingToCertificationIntegrities < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :certification_integrities, :claimed_at, :datetime
    add_reference :certification_integrities, :claimed_by, null: true, foreign_key: false, index: { algorithm: :concurrently }
  end
end
