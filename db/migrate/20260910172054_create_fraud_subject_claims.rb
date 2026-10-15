class CreateFraudSubjectClaims < ActiveRecord::Migration[8.1]
  def change
    create_table :fraud_subject_claims do |t|
      # One row per person: the unique index is what makes two reviewers
      # opening the same person at once resolve to a single holder.
      t.references :subject, null: false, foreign_key: { to_table: :users }, index: { unique: true }
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.datetime :claimed_at, null: false

      t.timestamps
    end
  end
end
