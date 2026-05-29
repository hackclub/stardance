class AddVerificationCheckedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :verification_checked_at, :datetime
  end
end
