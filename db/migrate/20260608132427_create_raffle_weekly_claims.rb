class CreateRaffleWeeklyClaims < ActiveRecord::Migration[8.1]
  def change
    create_table :raffle_weekly_claims do |t|
      t.references :participant, null: false, foreign_key: { to_table: :raffle_participants }
      t.references :week, null: false, foreign_key: { to_table: :raffle_weeks }
      t.timestamps
    end

    add_index :raffle_weekly_claims, [ :participant_id, :week_id ], unique: true
  end
end
