class CreateCertificationIntegrities < ActiveRecord::Migration[8.1]
  def change
    create_table :certification_integrities do |t|
      t.references :ship_event, null: false, index: { unique: true }, foreign_key: { to_table: :post_ship_events }
      t.references :reviewer, null: true, foreign_key: { to_table: :users }

      t.integer :status, null: false, default: 0
      t.integer :flags, null: false, default: 0

      t.datetime :reviewed_at
      t.text :decision_justification
      t.integer :deduction_minutes

      t.timestamps
    end

    add_index :certification_integrities, :status
  end
end
