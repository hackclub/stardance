class CreateCertificationPermanentRejectionNominations < ActiveRecord::Migration[8.1]
  def change
    create_table :certification_permanent_rejection_nominations do |t|
      t.references :project, null: false, foreign_key: true
      t.references :reviewable, polymorphic: true, null: false, index: { name: "index_permanent_rejections_reviewable" }
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.references :decided_by, foreign_key: { to_table: :users }
      t.text :reason, null: false
      t.integer :status, null: false, default: 0
      t.datetime :decided_at

      t.timestamps
    end

    add_index :certification_permanent_rejection_nominations, :project_id,
      unique: true, where: "status IN (0, 1)", name: "index_permanent_rejections_active_project"
    add_check_constraint :certification_permanent_rejection_nominations,
      "status IN (0, 1, 2)", name: "permanent_rejection_status"
  end
end
