class AddFraudReviewPayoutToReviewables < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  REVIEWABLE_TABLES = %i[project_reports shop_orders certification_integrities].freeze

  def change
    REVIEWABLE_TABLES.each do |table|
      add_column table, :fraud_review_payout_id, :bigint
      add_index table, :fraud_review_payout_id, algorithm: :concurrently

      # Every one of these tables is small (project_reports 506,
      # certification_integrities 4.5k, shop_orders 15k), so validating the key
      # up front costs milliseconds rather than a long lock.
      safety_assured do
        add_foreign_key table, :fraud_review_payouts, column: :fraud_review_payout_id
      end
    end
  end
end
