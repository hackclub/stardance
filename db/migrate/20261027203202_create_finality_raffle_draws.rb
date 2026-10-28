class CreateFinalityRaffleDraws < ActiveRecord::Migration[8.1]
  def change
    create_table :finality_raffle_draws do |t|
      t.string :key, null: false
      t.datetime :frozen_at
      t.references :frozen_by, foreign_key: { to_table: :users }
      t.integer :entry_count, null: false, default: 0
      t.integer :participant_count, null: false, default: 0
      t.timestamps
    end
    add_index :finality_raffle_draws, :key, unique: true

    create_table :finality_raffle_entries do |t|
      t.references :draw, null: false, foreign_key: { to_table: :finality_raffle_draws }
      t.references :user, null: false, foreign_key: true
      # Keep the original ship ID for the audit trail even if its post is deleted.
      t.bigint :ship_event_id, null: false
      t.datetime :shipped_at, null: false
      t.timestamps
    end
    add_index :finality_raffle_entries, [ :draw_id, :ship_event_id ], unique: true

    create_table :finality_raffle_selections do |t|
      t.references :draw, null: false, foreign_key: { to_table: :finality_raffle_draws }
      t.references :user, null: false, foreign_key: true
      t.string :prize_key, null: false
      t.integer :slot, null: false
      t.integer :entry_count, null: false
      t.integer :pool_entry_count, null: false
      t.references :selected_by, null: false, foreign_key: { to_table: :users }
      t.datetime :voided_at
      t.references :voided_by, foreign_key: { to_table: :users }
      t.text :void_reason
      t.timestamps
    end
    add_index :finality_raffle_selections, [ :draw_id, :prize_key, :slot ],
              unique: true, where: "voided_at IS NULL", name: "finality_raffle_one_active_selection_per_slot"
    add_index :finality_raffle_selections, [ :draw_id, :user_id ],
              unique: true, where: "voided_at IS NULL", name: "finality_raffle_one_prize_per_person"
    add_check_constraint :finality_raffle_selections,
                         "slot > 0 AND entry_count > 0 AND pool_entry_count >= entry_count",
                         name: "finality_raffle_positive_counts"
    add_check_constraint :finality_raffle_selections,
                         "(voided_at IS NULL AND voided_by_id IS NULL AND void_reason IS NULL) OR " \
                         "(voided_at IS NOT NULL AND voided_by_id IS NOT NULL AND void_reason IS NOT NULL AND length(trim(void_reason)) > 0)",
                         name: "finality_raffle_void_requires_reason"
  end
end
