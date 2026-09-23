class AddCountryToShopOrders < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :shop_orders, :country, :string, limit: 2
    add_index :shop_orders, :country, algorithm: :concurrently
  end
end
