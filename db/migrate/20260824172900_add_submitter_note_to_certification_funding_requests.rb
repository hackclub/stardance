class AddSubmitterNoteToCertificationFundingRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_funding_requests, :submitter_note, :text
  end
end
