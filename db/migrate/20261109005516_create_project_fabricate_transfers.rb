class CreateProjectFabricateTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :project_fabricate_transfers do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
