class AddPrizesWaivedToCertificationFundingRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_funding_requests, :prizes_waived, :boolean, default: false, null: false
  end
end
