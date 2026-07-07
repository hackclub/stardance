class AddFraudPayoutLineIdToShopOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_orders, :fraud_payout_line_id, :bigint unless column_exists?(:shop_orders, :fraud_payout_line_id)
  end
end
