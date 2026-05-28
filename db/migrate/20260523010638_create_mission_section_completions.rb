class CreateMissionSectionCompletions < ActiveRecord::Migration[8.1]
  def change
    create_table :mission_section_completions do |t|
      t.references :project, null: false, foreign_key: true
      t.references :mission, null: false, foreign_key: true
      t.references :mission_step,
                   null: false,
                   foreign_key: { to_table: :mission_steps, on_delete: :cascade }
      t.datetime :completed_at, null: false

      t.timestamps
    end

    add_index :mission_section_completions,
              [ :project_id, :mission_step_id ],
              unique: true,
              name: "index_mission_section_completions_unique"
  end
end
