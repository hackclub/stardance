class CreateProjectMentions < ActiveRecord::Migration[8.1]
  def change
    create_table :project_mentions do |t|
      t.references :project, null: false, foreign_key: true
      t.references :reviewer, null: true, foreign_key: { to_table: :users }
      t.string :platform
      t.string :url
      t.integer :metric_value
      t.string :metric_name
      t.datetime :approved_at
      t.datetime :rejected_at
      t.text :reviewer_notes

      t.timestamps
    end
  end
end
