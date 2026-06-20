class CreateRaffleDraws < ActiveRecord::Migration[8.1]
  def change
    create_table :raffle_draws do |t|
      t.references :week, null: false, foreign_key: { to_table: :raffle_weeks }
      t.references :winner_participant, null: false, foreign_key: { to_table: :raffle_participants }
      t.string :status, null: false, default: "active"
      t.text :void_reason
      t.datetime :drawn_at, null: false
      t.datetime :voided_at
      t.timestamps
    end

    add_index :raffle_draws, [ :week_id, :status ]
  end
end
