class AddShopItemIdToShopSuggestions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :shop_suggestions, :shop_item, index: { algorithm: :concurrently }
  end
end
