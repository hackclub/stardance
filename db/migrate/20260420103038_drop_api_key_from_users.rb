class DropApiKeyFromUsers < ActiveRecord::Migration[8.1]
  def change
    safety_assured { remove_index :users, :api_key, if_exists: true }
    safety_assured { remove_column :users, :api_key, :string }
  end
end
