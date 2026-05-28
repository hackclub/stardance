class CreateShopCategoriesAndSources < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_categories do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.string :hub_title, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :shop_categories, :slug, unique: true
    add_index :shop_categories, :position

    create_table :shop_sources do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :shop_sources, :slug, unique: true
    add_index :shop_sources, :position

    create_table :shop_item_categories do |t|
      t.references :shop_item, null: false, foreign_key: true
      t.references :shop_category, null: false, foreign_key: true
      t.timestamps
    end
    add_index :shop_item_categories, [ :shop_item_id, :shop_category_id ], unique: true, name: "index_shop_item_categories_unique"

    create_table :shop_item_sources do |t|
      t.references :shop_item, null: false, foreign_key: true
      t.references :shop_source, null: false, foreign_key: true
      t.timestamps
    end
    add_index :shop_item_sources, [ :shop_item_id, :shop_source_id ], unique: true, name: "index_shop_item_sources_unique"
  end
end
