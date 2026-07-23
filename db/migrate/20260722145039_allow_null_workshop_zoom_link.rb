class AllowNullWorkshopZoomLink < ActiveRecord::Migration[8.1]
  def change
    change_column_null :workshops, :zoom_link, true
  end
end
