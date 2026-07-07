class CreateFraudPayoutLines < ActiveRecord::Migration[8.1]
  def change
    create_table :fraud_payout_lines, if_not_exists: true do |t|
      t.references :fraud_payout_run, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :order_count
      t.integer :amount

      t.timestamps
    end
  end
end
