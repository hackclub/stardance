class CreateShopOrderModifierSelections < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_order_modifier_selections do |t|
      t.references :shop_order, null: false, foreign_key: true
      t.references :shop_item_modifier, null: false, foreign_key: true
      t.integer :frozen_modifier_price, null: false, default: 0

      t.timestamps
    end

    add_index :shop_order_modifier_selections,
              [ :shop_order_id, :shop_item_modifier_id ],
              unique: true,
              name: "idx_modifier_selections_unique"
  end
end
