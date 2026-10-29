class CreatePrivacyTokenUses < ActiveRecord::Migration[8.1]
  def change
    create_table :privacy_token_uses, primary_key: :jti, id: :string do |t|
      t.datetime :used_at, null: false
    end
    add_index :privacy_token_uses, :used_at
  end
end
