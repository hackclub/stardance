class AddExpiresAtToHCBCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :hcb_credentials, :expires_at, :datetime
  end
end
