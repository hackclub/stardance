class CreateFraudPayoutRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :fraud_payout_runs, if_not_exists: true do |t|
      t.string :aasm_state
      t.datetime :period_start
      t.datetime :period_end
      t.integer :total_orders
      t.integer :total_amount
      t.datetime :approved_at
      t.bigint :approved_by_user_id

      t.timestamps
    end
  end
end
