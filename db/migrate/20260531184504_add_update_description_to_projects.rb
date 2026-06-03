class AddUpdateDescriptionToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :update_description, :text
  end
end
