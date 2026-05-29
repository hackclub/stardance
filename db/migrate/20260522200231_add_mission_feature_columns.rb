class AddMissionFeatureColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :missions, :submission_guide, :text
    add_column :missions, :estimated_completion_minutes, :integer
    add_column :missions, :default_project_title, :string
    add_column :missions, :default_project_description, :text
  end
end
