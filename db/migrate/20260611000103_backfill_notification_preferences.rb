class BackfillNotificationPreferences < ActiveRecord::Migration[8.1]
  # Backfill new user_notification_preferences rows from the legacy boolean
  # columns on user_preferences (+ users.mission_review_notifications).
  # Dead column user_preferences.send_notifications_for_followed_users is
  # intentionally skipped — it has no readers.
  disable_ddl_transaction!

  def up
    safety_assured do
      execute(<<~SQL)
        INSERT INTO user_notification_preferences (user_id, category, slack_enabled, email_enabled, created_at, updated_at)
        SELECT user_id, 'new_follower', send_notifications_for_new_followers, NULL, NOW(), NOW()
        FROM user_preferences
        ON CONFLICT (user_id, category) DO NOTHING;
      SQL

      execute(<<~SQL)
        INSERT INTO user_notification_preferences (user_id, category, slack_enabled, email_enabled, created_at, updated_at)
        SELECT user_id, 'followed_devlog_created', send_notifications_for_followed_projects, NULL, NOW(), NOW()
        FROM user_preferences
        ON CONFLICT (user_id, category) DO NOTHING;
      SQL

      execute(<<~SQL)
        INSERT INTO user_notification_preferences (user_id, category, slack_enabled, email_enabled, created_at, updated_at)
        SELECT user_id, 'project_comment_received', send_notifications_for_new_comments, NULL, NOW(), NOW()
        FROM user_preferences
        ON CONFLICT (user_id, category) DO NOTHING;
      SQL

      execute(<<~SQL)
        INSERT INTO user_notification_preferences (user_id, category, slack_enabled, email_enabled, created_at, updated_at)
        SELECT user_id, 'stardust_balance_changed', stardust_balance_notifications, NULL, NOW(), NOW()
        FROM user_preferences
        ON CONFLICT (user_id, category) DO NOTHING;
      SQL

      execute(<<~SQL)
        INSERT INTO user_notification_preferences (user_id, category, slack_enabled, email_enabled, created_at, updated_at)
        SELECT id, 'mission_submission_pending_for_reviewer', mission_review_notifications, NULL, NOW(), NOW()
        FROM users
        ON CONFLICT (user_id, category) DO NOTHING;
      SQL
    end
  end

  def down
    safety_assured do
      execute("DELETE FROM user_notification_preferences WHERE category IN ('new_follower', 'followed_devlog_created', 'project_comment_received', 'stardust_balance_changed', 'mission_submission_pending_for_reviewer')")
    end
  end
end
