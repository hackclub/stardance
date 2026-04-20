class Airtable::DevlogSyncJob < Airtable::BaseSyncJob
  def table_name = "_devlogs"

  def records = Post::Devlog.includes(:post)

  def field_mapping(devlog)
    post = devlog.post
    {
      "body" => devlog.body,
      "duration_seconds" => devlog.duration_seconds,
      "likes_count" => devlog.likes_count,
      "comments_count" => devlog.comments_count,
      "project_id" => post&.project_id&.to_s,
      "user_id" => post&.user_id&.to_s,
      "created_at" => devlog.created_at,
      "synced_at" => Time.now,
      "star_id" => devlog.id.to_s
    }
  end
end
