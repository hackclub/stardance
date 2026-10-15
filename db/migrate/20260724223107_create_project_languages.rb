class CreateProjectLanguages < ActiveRecord::Migration[8.1]
  def change
    create_table :project_languages do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true, name: "index_project_languages_on_project_id_unique" }
      t.integer :status, default: 0, null: false
      t.jsonb :language_stats
      t.datetime :last_synced_at
      t.text :error_message

      t.timestamps
    end
    add_index :project_languages, :last_synced_at
    add_index :project_languages, :status
    add_index :project_languages, :language_stats, using: :gin
  end
end
