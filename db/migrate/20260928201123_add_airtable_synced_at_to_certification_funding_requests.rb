class AddAirtableSyncedAtToCertificationFundingRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_funding_requests, :airtable_synced_at, :datetime
  end
end
