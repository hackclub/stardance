class EnqueueHackatimeProjectSnapshotBackfill < ActiveRecord::Migration[8.1]
  def up
    # The job defers enqueueing until commit; Solid Queue uses a separate DB.
    OneTime::BackfillHackatimeProjectSnapshotsJob.perform_later if Rails.env.production?
  end

  def down
    # Recovered metadata is safe to retain. Do not enqueue again on rollback.
  end
end
