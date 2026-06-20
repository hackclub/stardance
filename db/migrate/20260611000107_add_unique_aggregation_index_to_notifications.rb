class AddUniqueAggregationIndexToNotifications < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Belt-and-suspenders to Notification.aggregate_or_build: even with the
  # pessimistic .lock, two concurrent notifies that both find no existing
  # unread row would each insert a fresh row. This enforces dedupe at the
  # DB level for aggregatable types; the model rescues RecordNotUnique
  # and retries the lookup.
  def change
    add_index :notifications,
              [ :recipient_id, :type, :group_key ],
              unique: true,
              where: "read_at IS NULL AND group_key IS NOT NULL",
              algorithm: :concurrently,
              name: "index_notifications_unique_unread_aggregate"
  end
end
