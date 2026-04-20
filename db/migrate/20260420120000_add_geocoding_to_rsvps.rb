class AddGeocodingToRsvps < ActiveRecord::Migration[8.0]
  def change
    add_column :rsvps, :geocoded_lat, :float
    add_column :rsvps, :geocoded_lon, :float
    add_column :rsvps, :geocoded_country, :string
    add_column :rsvps, :geocoded_subdivision, :string
  end
end
