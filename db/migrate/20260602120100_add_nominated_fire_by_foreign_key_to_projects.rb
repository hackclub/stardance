class AddNominatedFireByForeignKeyToProjects < ActiveRecord::Migration[8.1]
  def up
    add_foreign_key :projects, :users, column: :nominated_fire_by_id, validate: false
  end

  def down
    remove_foreign_key :projects, :users, column: :nominated_fire_by_id
  end
end
