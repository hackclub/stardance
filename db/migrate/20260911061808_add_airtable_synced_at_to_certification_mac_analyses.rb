class AddAirtableSyncedAtToCertificationMACAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_mac_analyses, :airtable_synced_at, :datetime
  end
end
