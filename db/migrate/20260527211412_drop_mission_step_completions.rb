class DropMissionStepCompletions < ActiveRecord::Migration[8.1]
  # The Mission::StepCompletion model, its controller, routes, and the
  # has_many associations on Project / Mission::Step were all removed in
  # the unify-sections refactor. mission_section_completions (keyed on
  # mission_step_id) is the replacement.
  def change
    drop_table :mission_step_completions do |t|
      t.datetime :completed_at
      t.datetime :created_at, null: false
      t.bigint :mission_step_id, null: false
      t.bigint :project_id, null: false
      t.datetime :updated_at, null: false
      t.index [ :mission_step_id ], name: "index_mission_step_completions_on_mission_step_id"
      t.index [ :project_id, :mission_step_id ], name: "index_mission_step_completions_unique", unique: true
      t.index [ :project_id ], name: "index_mission_step_completions_on_project_id"
      t.foreign_key :mission_steps
      t.foreign_key :projects
    end
  end
end
