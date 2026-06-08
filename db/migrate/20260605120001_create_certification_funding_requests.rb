class CreateCertificationFundingRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :certification_funding_requests do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :reviewer, null: true, foreign_key: { to_table: :users }

      t.integer :complexity_tier, null: false
      t.integer :requested_amount_cents, null: false
      t.integer :approved_amount_cents
      t.integer :status, null: false, default: 0

      t.text :feedback
      t.text :internal_reason

      t.integer :stardust_earned
      t.integer :discount_stardust_awarded

      t.datetime :claimed_at
      t.datetime :claim_expires_at
      t.datetime :decided_at
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_index :certification_funding_requests, [ :status, :claim_expires_at ],
      name: "idx_funding_requests_on_status_claim_expires"
    add_index :certification_funding_requests, :decided_at
    # One open (pending) request per project, mirroring the ship-review queue.
    add_index :certification_funding_requests, :project_id,
      unique: true, where: "status = 0",
      name: "index_funding_requests_unique_pending_project"
  end
end
