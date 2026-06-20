class AddHardwareStageToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :hardware_stage, :string
  end
end
