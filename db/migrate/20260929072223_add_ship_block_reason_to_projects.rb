class AddShipBlockReasonToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :ship_block_reason, :text
  end
end
