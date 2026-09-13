class AddFraudReviewPayoutsDisabledAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :fraud_review_payouts_disabled_at, :datetime
  end
end
