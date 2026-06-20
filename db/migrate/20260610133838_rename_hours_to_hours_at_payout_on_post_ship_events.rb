class RenameHoursToHoursAtPayoutOnPostShipEvents < ActiveRecord::Migration[8.1]
  def change
    safety_assured { rename_column :post_ship_events, :hours, :hours_at_payout }
  end
end
