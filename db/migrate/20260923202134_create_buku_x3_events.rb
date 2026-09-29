class CreateBukuX3Events < ActiveRecord::Migration[8.1]
  def change
    create_table :buku_x3_events do |t|
      t.string :key, null: false
      t.datetime :unlocked_at
      t.integer :destruction_minutes, null: false, default: 0

      t.timestamps
    end
    add_index :buku_x3_events, :key, unique: true
    add_check_constraint :buku_x3_events, "destruction_minutes BETWEEN 0 AND 300000", name: "buku_x3_destruction_bounds"
  end
end
