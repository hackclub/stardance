class AddSaleWindowToShopItems < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_items, :sale_starts_at, :datetime
    add_column :shop_items, :sale_ends_at, :datetime
    add_column :shop_items, :sale_step_percentage, :integer, default: 0, null: false
    add_column :shop_items, :sale_min_percentage, :integer, default: 0, null: false
    add_column :shop_items, :sale_name, :string
  end
end
