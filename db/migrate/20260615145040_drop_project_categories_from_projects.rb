class DropProjectCategoriesFromProjects < ActiveRecord::Migration[8.1]
  def change
    safety_assured { remove_column :projects, :project_categories, :string, array: true, default: [] }
  end
end
