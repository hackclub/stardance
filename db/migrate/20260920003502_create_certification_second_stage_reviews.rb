class CreateCertificationSecondStageReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :certification_second_stage_reviews do |t|
      t.references :reviewable, polymorphic: true, null: false
      t.references :reviewer, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.datetime :claimed_at
      t.datetime :claim_expires_at
      t.datetime :decided_at
      t.text :feedback
      t.text :internal_reason
      t.integer :stardust_earned
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    # One second stage per T1 review: a T1 approval opens exactly one, and a
    # re-opened one is reused rather than stacked.
    add_index :certification_second_stage_reviews,
              [ :reviewable_type, :reviewable_id ],
              unique: true,
              name: "index_second_stage_reviews_unique_reviewable"

    # The queue hands out the oldest unclaimed pending row, mirroring
    # idx_funding_requests_on_status_claim_expires.
    add_index :certification_second_stage_reviews,
              [ :status, :claim_expires_at ],
              name: "idx_second_stage_reviews_on_status_claim_expires"

    add_index :certification_second_stage_reviews, :decided_at
  end
end
