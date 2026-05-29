class CreateMissionGuideVariants < ActiveRecord::Migration[8.1]
  def change
    create_table :mission_guide_variants do |t|
      t.references :mission, null: false, foreign_key: true
      t.string :language, null: false
      t.text :body, null: false
      t.integer :position, null: false, default: 0
      t.datetime :body_updated_at

      t.timestamps
    end

    add_index :mission_guide_variants,
              "mission_id, LOWER(language)",
              unique: true,
              name: "index_mission_guide_variants_unique_language"
  end
end
