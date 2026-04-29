# frozen_string_literal: true

class Airtable::UserMetricsSyncJob < Airtable::BaseSyncJob
  def table_name = "_users"

  # Only sync users with emails to match the UserSyncJob pattern
  def records = User.where.not(email: [ nil, "" ])

  # CRITICAL: Use same primary key as UserSyncJob to upsert into existing records
  def primary_key_field = "email"

  # Use a different synced_at field so this job has its own tracking
  def synced_at_field = :metrics_synced_at

  def field_mapping(user)
    {
      "email" => user.email, # Primary key for matching existing records
      "Loops - message_count_14d" => user.message_count_14d,
      "Loops - support_message_count_14d" => user.support_message_count_14d,
      "Loops - projects_count" => user.projects_count,
      "Loops - projects_shipped_count" => user.projects_shipped_count,
      "projects_and_slack_metrics_synced_at" => Time.now
    }
  end
end
