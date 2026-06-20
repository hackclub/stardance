class ActivityDailySummaryJob < ApplicationJob
  queue_as :default

  CHANNEL_ID = "C0AR0M43H61" # stardance-construction

  def perform
    since = 1.day.ago

    SendSlackDmJob.perform_later(
      CHANNEL_ID,
      "Daily Stardance Summary",
      blocks_path: "notifications/activity_daily_summary",
      locals: build_locals(since)
    )
  end

  private

  def build_locals(since)
    {
      total_users: User.deduplicated_signup_count,
      new_users: new_signup_count(since),
      active_users: daily_active_users(since),
      new_devlogs: Post::Devlog.where(created_at: since..).count,
      new_ships: Post::ShipEvent.where(created_at: since..).count,
      new_likes: Like.where(created_at: since..).count,
      new_comments: Comment.where(created_at: since..).count,
      new_reposts: Post::Repost.where(created_at: since..).count,
      virality_factor: Signup.virality_factor,
      since: since
    }
  end

  def new_signup_count(since)
    ApplicationRecord.connection.select_value(
      ApplicationRecord.sanitize_sql_array(
        [ "SELECT COUNT(*) FROM materialized_all_signups WHERE first_seen_at_utc >= ?", since ]
      )
    )
  end

  # Platform DAU: distinct signed-in (non-banned) users with an Ahoy visit in
  # the window. Ahoy lives in its own database and tracking is off without
  # AHOY_DB_URL, so this returns nil (rendered as n/a) when unavailable.
  def daily_active_users(since)
    return nil unless ENV["AHOY_DB_URL"].present?

    user_ids = Ahoy::Visit.where(started_at: since..).where.not(user_id: nil).distinct.pluck(:user_id)
    User.where(id: user_ids, banned: false).count
  end
end
