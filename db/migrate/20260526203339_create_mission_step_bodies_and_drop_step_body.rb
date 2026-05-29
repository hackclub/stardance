class CreateMissionStepBodiesAndDropStepBody < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :mission_step_bodies do |t|
      t.references :mission_step, null: false, foreign_key: { to_table: :mission_steps }
      t.string :language, null: false
      t.text :body, null: false, default: ""
      t.datetime :body_updated_at

      t.timestamps
    end

    add_index :mission_step_bodies,
              "mission_step_id, LOWER(language)",
              unique: true,
              algorithm: :concurrently,
              name: "index_mission_step_bodies_unique_language"

    safety_assured { remove_column :mission_steps, :body, :text }
  end
end
