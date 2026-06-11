class AddHasPresentableHardwareProjectToUsers < ActiveRecord::Migration[8.1]
  def change
    # Manually granted (after a showcase-form review) to unlock the Outpost
    # Ticket shop item via the achievement-gate mechanism.
    add_column :users, :has_presentable_hardware_project, :boolean, default: false, null: false
  end
end
