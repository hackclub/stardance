class AlterShopSuggestionsForPublicFeature < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    safety_assured do
      rename_column :shop_suggestions, :item, :name
      rename_column :shop_suggestions, :explanation, :description
      rename_column :shop_suggestions, :link, :url
    end

    add_column :shop_suggestions, :usd_cost, :decimal, precision: 8, scale: 2
    add_column :shop_suggestions, :aasm_state, :string, null: false, default: "pending"
    add_column :shop_suggestions, :rejection_reason, :string

    add_index :shop_suggestions, :aasm_state, algorithm: :concurrently
  end
end
