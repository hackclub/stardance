class CreateWorkshops < ActiveRecord::Migration[8.1]
  def change
    create_table :workshops do |t|
      t.string :title, null: false
      t.text :description
      t.string :zoom_link, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.datetime :rsvps_notified_at

      t.timestamps
    end

    add_index :workshops, :starts_at
  end
end
