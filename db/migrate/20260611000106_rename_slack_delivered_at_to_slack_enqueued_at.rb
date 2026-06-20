class RenameSlackDeliveredAtToSlackEnqueuedAt < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      rename_column :notifications, :slack_delivered_at, :slack_enqueued_at
    end
  end
end
