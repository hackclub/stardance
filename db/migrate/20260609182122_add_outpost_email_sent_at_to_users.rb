class AddOutpostEmailSentAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :outpost_email_sent_at, :datetime
  end
end
