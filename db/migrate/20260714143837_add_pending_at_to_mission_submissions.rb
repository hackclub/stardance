class AddPendingAtToMissionSubmissions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :mission_submissions, :pending_at, :datetime

    add_index :mission_submissions, [ :status, :pending_at ], algorithm: :concurrently

    reversible do |dir|
      dir.up do
        safety_assured do
          # Queue age counts from the last review (the ship certification, or a
          # mission review that was undone or resubmitted), not from ship time.
          # Backfill from the ship cert verdict; submissions that never reached
          # the queue stay NULL.
          execute <<~SQL
            UPDATE mission_submissions SET pending_at = certs.decided_at
            FROM (
              SELECT post_ship_event_id, MAX(COALESCE(decided_at, updated_at)) AS decided_at
              FROM certification_ship_reviews
              WHERE status = 1 AND post_ship_event_id IS NOT NULL
              GROUP BY post_ship_event_id
            ) certs
            WHERE mission_submissions.ship_event_id = certs.post_ship_event_id
              AND mission_submissions.status <> 'awaiting_certification'
          SQL

          execute <<~SQL
            UPDATE mission_submissions SET pending_at = created_at
            WHERE pending_at IS NULL AND status = 'pending'
          SQL
        end
      end
    end
  end
end
