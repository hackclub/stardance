class ValidateNominatedFireByForeignKeyOnProjects < ActiveRecord::Migration[8.1]
  def up
    validate_foreign_key :projects, :users, column: :nominated_fire_by_id
  end

  def down
  end
end
