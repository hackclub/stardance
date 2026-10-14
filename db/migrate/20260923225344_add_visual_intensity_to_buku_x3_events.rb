class AddVisualIntensityToBukuX3Events < ActiveRecord::Migration[8.1]
  def change
    add_column :buku_x3_events, :visual_intensity, :integer, null: false, default: 100
    add_check_constraint :buku_x3_events, "visual_intensity BETWEEN 0 AND 200", name: "buku_x3_visual_intensity_range", validate: false
  end
end
