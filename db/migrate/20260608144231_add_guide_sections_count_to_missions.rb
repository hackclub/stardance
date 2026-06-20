class AddGuideSectionsCountToMissions < ActiveRecord::Migration[8.1]
  def change
    add_column :missions, :guide_sections_count, :integer
  end
end
