class CreateRaffleTables < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
    create_table :raffle_weeks do |t|
      t.integer :number, null: false
      t.string :status, null: false, default: "active"
      t.datetime :opened_at
      t.datetime :closed_at
      t.string :prize, null: false, default: "AMD RX 9060 XT"
      t.datetime :drawn_at

      t.timestamps
    end

    add_index :raffle_weeks, :number, unique: true
    add_index :raffle_weeks, :status, unique: true, where: "status = 'active'",
                                                name: "index_raffle_weeks_one_active"

    create_table :raffle_participants do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.references :signup_week, foreign_key: { to_table: :raffle_weeks }, index: false
      t.string :code, null: false
      t.boolean :eligible, null: false, default: true

      t.timestamps
    end

    add_index :raffle_participants, :code, unique: true

    add_reference :raffle_weeks, :winner_participant,
                  foreign_key: { to_table: :raffle_participants }, index: false

    create_table :raffle_referrals do |t|
      t.references :participant, null: false, index: false,
                   foreign_key: { to_table: :raffle_participants }
      t.references :referred_user, null: false, index: { unique: true },
                   foreign_key: { to_table: :users }
      t.references :credited_week, index: false,
                   foreign_key: { to_table: :raffle_weeks }
      t.string :channel, null: false, default: "web"
      t.string :status, null: false, default: "pending"
      t.string :raw_ref
      t.datetime :verified_at

      t.timestamps
    end

    add_index :raffle_referrals, [ :credited_week_id, :status, :participant_id ],
              name: "index_raffle_referrals_on_week_status_participant"
    add_index :raffle_referrals, [ :participant_id, :status, :credited_week_id ],
              name: "index_raffle_referrals_on_participant_status_week"
    add_index :raffle_referrals, [ :status, :created_at ],
              name: "index_raffle_referrals_on_status_created_at"
    end
  end
end
