class AddDiscardedAtToShopSuggestions < ActiveRecord::Migration[8.1]
  def change
    add_column :shop_suggestions, :discarded_at, :datetime
  end
end
