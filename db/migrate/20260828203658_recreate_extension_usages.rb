class RecreateExtensionUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :extension_usages do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :extension_usages, [ :project_id, :created_at ]
  end
end
