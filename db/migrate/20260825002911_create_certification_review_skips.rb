class CreateCertificationReviewSkips < ActiveRecord::Migration[8.1]
  def change
    create_table :certification_review_skips do |t|
      t.references :user, null: false, foreign_key: true
      t.references :reviewable, polymorphic: true, null: false
      t.datetime :skipped_at, null: false

      t.timestamps
    end

    # One skip row per reviewer per submission; re-skipping refreshes skipped_at
    # rather than piling up rows. Also serves the per-reviewer cooldown lookup.
    add_index :certification_review_skips,
              [ :user_id, :reviewable_type, :reviewable_id ],
              unique: true,
              name: "index_review_skips_unique_reviewer_reviewable"
  end
end
