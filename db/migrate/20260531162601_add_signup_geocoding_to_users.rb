class AddSignupGeocodingToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ip_address, :string
    add_column :users, :user_agent, :string
    add_column :users, :geocoded_lat, :float
    add_column :users, :geocoded_lon, :float
    add_column :users, :geocoded_country, :string
    add_column :users, :geocoded_subdivision, :string
  end
end
