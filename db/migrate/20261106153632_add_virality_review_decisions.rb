class AddViralityReviewDecisions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LOCK_RETRIES = 3
  LOCK_RETRY_DELAY = 10.seconds

  def up
    # Release the existing table's exclusive lock before building the decision table.
    with_lock_retries do
      add_column :project_mentions, :approved_tier, :string unless column_exists?(:project_mentions, :approved_tier)
      unless check_constraint_exists?(:project_mentions, name: "project_mentions_approved_tier")
        add_check_constraint :project_mentions, "approved_tier IS NULL OR approved_tier IN ('good', 'great')", name: "project_mentions_approved_tier", validate: false
      end
    end

    with_lock_retries do
      # The table and all its indexes/constraints commit together, making reruns safe.
      next if table_exists?(:virality_decisions)

      create_table :virality_decisions do |t|
        t.references :project_mention, null: false, foreign_key: true
        t.references :reviewer, null: false, foreign_key: { to_table: :users }
        t.references :cancelled_by, foreign_key: { to_table: :users }
        t.string :action, null: false
        t.string :tier
        t.string :status, null: false, default: "scheduled"
        t.text :reason
        t.jsonb :evidence, null: false, default: {}
        t.jsonb :result, null: false, default: {}
        t.datetime :process_at, null: false
        t.datetime :processed_at
        t.datetime :cancelled_at
        t.text :error_message
        t.timestamps
      end

      add_index :virality_decisions, :project_mention_id, unique: true,
        where: "status = 'scheduled'", name: "one_scheduled_virality_decision_per_mention"
      add_index :virality_decisions, :process_at, where: "status = 'scheduled'", name: "due_virality_decisions"
      add_check_constraint :virality_decisions, "action IN ('approve', 'reject', 'reverse')", name: "virality_decisions_action"
      add_check_constraint :virality_decisions, "status IN ('scheduled', 'cancelled', 'processed', 'failed')", name: "virality_decisions_status"
      add_check_constraint :virality_decisions, "action <> 'approve' OR (tier IS NOT NULL AND tier IN ('good', 'great'))", name: "virality_decisions_approval_tier"
    end
  end

  def down
    with_lock_retries do
      drop_table :virality_decisions if table_exists?(:virality_decisions)
    end
    with_lock_retries do
      if check_constraint_exists?(:project_mentions, name: "project_mentions_approved_tier")
        remove_check_constraint :project_mentions, name: "project_mentions_approved_tier"
      end
      remove_column :project_mentions, :approved_tier if column_exists?(:project_mentions, :approved_tier)
    end
  end

  private

    def with_lock_retries
      retries = 0
      begin
        connection.transaction(requires_new: true) { yield }
      rescue ActiveRecord::LockWaitTimeout
        raise if retries >= LOCK_RETRIES

        retries += 1
        say "Lock timeout. Retrying in #{LOCK_RETRY_DELAY} seconds (#{retries}/#{LOCK_RETRIES})..."
        sleep LOCK_RETRY_DELAY
        retry
      end
    end
end
