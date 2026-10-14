class AddApiKeyToUsersForPublicApi < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :users, :api_key, :string
    add_index :users, :api_key, unique: true, algorithm: :concurrently
  end
end
