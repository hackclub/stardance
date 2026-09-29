class ValidateBukuX3VisualIntensityRange < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :buku_x3_events, name: "buku_x3_visual_intensity_range"
  end
end
