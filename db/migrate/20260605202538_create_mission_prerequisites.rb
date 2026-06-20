class CreateMissionPrerequisites < ActiveRecord::Migration[8.1]
  def change
    create_table :mission_prerequisites do |t|
      t.references :prerequisite_mission, null: false, foreign_key: { to_table: :missions }
      t.references :dependent_mission, null: false, foreign_key: { to_table: :missions }
      t.timestamps
    end

    add_index :mission_prerequisites, [ :prerequisite_mission_id, :dependent_mission_id ],
              unique: true, name: "idx_mission_prereqs_unique"
  end
end
