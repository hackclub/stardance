class CreateShopItemModifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_item_modifiers do |t|
      t.references :shop_item, null: false, foreign_key: true
      t.string :name, null: false
      t.string :group_name
      t.integer :ticket_cost, null: false, default: 0
      t.decimal :usd_cost, precision: 10, scale: 2
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0

      t.boolean :enabled_us
      t.boolean :enabled_eu
      t.boolean :enabled_uk
      t.boolean :enabled_ca
      t.boolean :enabled_au
      t.boolean :enabled_in
      t.boolean :enabled_xx

      t.decimal :usd_offset_us, precision: 10, scale: 2
      t.decimal :usd_offset_eu, precision: 10, scale: 2
      t.decimal :usd_offset_uk, precision: 10, scale: 2
      t.decimal :usd_offset_ca, precision: 10, scale: 2
      t.decimal :usd_offset_au, precision: 10, scale: 2
      t.decimal :usd_offset_in, precision: 10, scale: 2
      t.decimal :usd_offset_xx, precision: 10, scale: 2

      t.timestamps
    end
  end
end
