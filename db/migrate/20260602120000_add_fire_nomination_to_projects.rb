class AddFireNominationToProjects < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :projects, :nominated_fire_at, :datetime
    add_reference :projects, :nominated_fire_by, null: true, index: { algorithm: :concurrently }
  end
end
