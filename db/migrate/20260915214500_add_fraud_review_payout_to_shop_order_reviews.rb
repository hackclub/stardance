class AddFraudReviewPayoutToShopOrderReviews < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :shop_order_reviews, :fraud_review_payout_id, :bigint
    add_index :shop_order_reviews, :fraud_review_payout_id, algorithm: :concurrently

    # shop_order_reviews holds a handful of rows, so validating the key up front
    # costs milliseconds rather than a long lock.
    safety_assured do
      add_foreign_key :shop_order_reviews, :fraud_review_payouts, column: :fraud_review_payout_id
    end
  end
end
