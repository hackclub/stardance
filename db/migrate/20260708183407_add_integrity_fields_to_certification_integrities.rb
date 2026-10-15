class AddIntegrityFieldsToCertificationIntegrities < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_integrities, :fraud_detection_data, :jsonb
  end
end
