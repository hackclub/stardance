class AddFrozenModifiersPriceToShopOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_orders, :frozen_modifiers_price, :integer, null: false, default: 0
  end
end
