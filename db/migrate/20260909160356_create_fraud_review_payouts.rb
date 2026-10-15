class CreateFraudReviewPayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :fraud_review_payouts do |t|
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.references :subject, null: false, foreign_key: { to_table: :users }
      t.references :fraud_payout_line, foreign_key: true

      t.integer :flag_count, null: false, default: 0
      t.integer :order_count, null: false, default: 0
      t.integer :integrity_count, null: false, default: 0

      # Exact formula result. Rounded to a whole number only when a payout run
      # is approved and writes the ledger entry.
      t.decimal :amount, precision: 10, scale: 2, null: false, default: 0

      # Set once nothing is left waiting on the subject. Until then the row is
      # the reviewer's running tally and is not payable.
      t.datetime :completed_at

      t.timestamps
    end
  end
end
