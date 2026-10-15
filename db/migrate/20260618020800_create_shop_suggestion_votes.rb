class CreateShopSuggestionVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_suggestion_votes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :shop_suggestion, null: false, foreign_key: true

      t.timestamps
    end
  end
end
