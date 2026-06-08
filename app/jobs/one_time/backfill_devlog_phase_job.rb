class OneTime::BackfillDevlogPhaseJob < ApplicationJob
  queue_as :literally_whenever

  # Stamps `phase` onto existing devlogs from their project's current
  # hardware_stage. Software projects (nil hardware_stage) keep phase nil and so
  # are unaffected by the build-only payout basis. Safe to run once: there is no
  # historical design->build transition yet, so the current stage is the only
  # phase any existing devlog could have been logged in.
  def perform
    sql = <<~SQL.squish
      UPDATE post_devlogs
      SET phase = projects.hardware_stage, updated_at = NOW()
      FROM posts
      INNER JOIN projects ON projects.id = posts.project_id
      WHERE posts.postable_type = 'Post::Devlog'
        AND posts.postable_id = post_devlogs.id
        AND projects.hardware_stage IS NOT NULL
        AND post_devlogs.phase IS NULL
    SQL

    affected = ActiveRecord::Base.connection.update(sql)
    Rails.logger.info "[BackfillDevlogPhase] Updated #{affected} devlogs"
  end
end
