class AddHoursAtShipToPostShipEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :post_ship_events, :hours_at_ship, :float
  end
end
