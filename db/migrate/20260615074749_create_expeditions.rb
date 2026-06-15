class CreateExpeditions < ActiveRecord::Migration[8.1]
  def change
    create_table :expeditions do |t|
      t.string :airtable_id, null: false
      t.string :title, null: false
      t.string :slug
      t.string :season
      t.date :date
      t.boolean :concluded, null: false, default: false
      t.string :venue_name
      t.string :venue_address
      t.string :city
      t.string :state
      t.string :country
      t.float :latitude
      t.float :longitude
      t.string :google_maps_url
      t.string :apple_maps_url
      t.string :channel_id
      t.string :ambassador_slack_id
      t.string :ambassador_name
      t.string :participant_slack_ids, array: true, null: false, default: []

      t.timestamps
    end

    add_index :expeditions, :airtable_id, unique: true
    add_index :expeditions, :slug, unique: true
    add_index :expeditions, [ :concluded, :date, :id ]
  end
end
