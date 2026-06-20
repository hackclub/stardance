class BackfillProjectFollowedPreferences < ActiveRecord::Migration[8.1]
  # The original BackfillNotificationPreferences mapped the legacy
  # send_notifications_for_new_followers boolean to the `new_follower`
  # category only. But the same legacy boolean ALSO gated project-follow
  # Slack DMs in projects_controller#follow. Without this migration,
  # every existing user who had project-follow Slack DMs enabled silently
  # loses them once the new preferences system goes live, because the
  # project_followed category has slack:false in the priority defaults.
  def up
    safety_assured do
      execute(<<~SQL)
        INSERT INTO user_notification_preferences (user_id, category, slack_enabled, email_enabled, created_at, updated_at)
        SELECT user_id, 'project_followed', slack_enabled, NULL, NOW(), NOW()
        FROM user_notification_preferences
        WHERE category = 'new_follower'
        ON CONFLICT (user_id, category) DO NOTHING;
      SQL
    end
  end

  def down
    safety_assured do
      execute("DELETE FROM user_notification_preferences WHERE category = 'project_followed'")
    end
  end
end
