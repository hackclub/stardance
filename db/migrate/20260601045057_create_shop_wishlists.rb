class CreateShopWishlists < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_wishlists do |t|
      t.references :user, null: false, foreign_key: true
      t.references :shop_item, null: false, foreign_key: true

      t.timestamps
    end

    add_index :shop_wishlists, [ :user_id, :shop_item_id ], unique: true
  end
end
