class CreateGrowthDailySnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :growth_daily_snapshots do |t|
      t.date :snapshot_on, null: false
      t.string :metric, null: false
      t.integer :new_users, null: false, default: 0
      t.integer :current_users, null: false, default: 0
      t.integer :reactivated_users, null: false, default: 0
      t.integer :resurrected_users, null: false, default: 0
      t.integer :at_risk_wau, null: false, default: 0
      t.integer :at_risk_mau, null: false, default: 0
      t.integer :dormant_users, null: false, default: 0
      t.jsonb :transitions, null: false, default: {}

      t.timestamps
    end

    add_index :growth_daily_snapshots, [ :metric, :snapshot_on ], unique: true
  end
end
