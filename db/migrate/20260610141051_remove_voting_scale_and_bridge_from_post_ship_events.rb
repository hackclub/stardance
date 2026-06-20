class RemoveVotingScaleAndBridgeFromPostShipEvents < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      remove_column :post_ship_events, :voting_scale_version, :integer, default: 2, null: false
      remove_column :post_ship_events, :bridge, :boolean, default: false, null: false
      remove_column :post_ship_events, :base_hours, :float
      remove_column :post_ship_events, :legacy_payout_deduction, :float
    end
  end
end
