class AddGuideUrlToMissions < ActiveRecord::Migration[8.1]
  def change
    add_column :missions, :guide_url, :string
  end
end
