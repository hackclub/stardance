class CreateCertificationReviewNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :certification_review_notes do |t|
      t.references :project, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body

      t.timestamps
    end
  end
end
