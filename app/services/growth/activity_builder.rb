# frozen_string_literal: true

module Growth
  # Fills user_activity_days for a range of days from the tables that record
  # what users did. Safe to re-run: sources merge into the days already there.
  class ActivityBuilder
    def initialize(from:, to:)
      @from = from
      @to = to
    end

    def call
      ApplicationRecord.connection.exec_update(actions_sql)
      merge_visits
    end

    private

    def window = @from.in_time_zone(UserActivityDay::TIME_ZONE)...(@to + 1).in_time_zone(UserActivityDay::TIME_ZONE)

    # Timestamps are stored in UTC without a zone; this turns one into its Eastern day.
    def day(column) = "(#{column} AT TIME ZONE 'UTC' AT TIME ZONE '#{UserActivityDay::TIME_ZONE}')::date"

    def actions_sql
      ApplicationRecord.sanitize_sql_array([ <<~SQL, { start: window.begin.utc, finish: window.end.utc, from: @from, to: @to, goal: StreakActivity::DAILY_GOAL_SECONDS } ])
        WITH actions(user_id, active_on, source) AS (
          SELECT posts.user_id, #{day("post_devlogs.created_at")}, 'devlog'
          FROM posts
          JOIN post_devlogs ON posts.postable_type = 'Post::Devlog' AND post_devlogs.id = posts.postable_id
          WHERE post_devlogs.created_at >= :start AND post_devlogs.created_at < :finish
            AND post_devlogs.deleted_at IS NULL AND NOT post_devlogs.tutorial

          UNION ALL
          SELECT posts.user_id, #{day("posts.created_at")}, 'ship'
          FROM posts
          WHERE posts.postable_type = 'Post::ShipEvent' AND posts.created_at >= :start AND posts.created_at < :finish

          UNION ALL
          SELECT user_id, activity_date, 'coding'
          FROM streak_activities
          WHERE activity_date BETWEEN :from AND :to AND coded_seconds >= :goal

          UNION ALL
          SELECT user_id, #{day("created_at")}, 'vote'
          FROM votes
          WHERE created_at >= :start AND created_at < :finish AND NOT discarded

          UNION ALL
          SELECT user_id, #{day("created_at")}, 'social'
          FROM likes
          WHERE created_at >= :start AND created_at < :finish

          UNION ALL
          SELECT user_id, #{day("created_at")}, 'social'
          FROM comments
          WHERE created_at >= :start AND created_at < :finish AND deleted_at IS NULL

          UNION ALL
          SELECT user_id, #{day("created_at")}, 'social'
          FROM post_reposts
          WHERE created_at >= :start AND created_at < :finish AND deleted_at IS NULL

          UNION ALL
          SELECT user_id, #{day("created_at")}, 'shop'
          FROM shop_orders
          WHERE created_at >= :start AND created_at < :finish

          UNION ALL
          SELECT user_id, rolled_on, 'daily_roll'
          FROM daily_rolls
          WHERE rolled_on BETWEEN :from AND :to
        )
        INSERT INTO user_activity_days (user_id, active_on, sources, created_at, updated_at)
        SELECT user_id, active_on, array_agg(DISTINCT source ORDER BY source), NOW(), NOW()
        FROM actions
        WHERE user_id IS NOT NULL
        GROUP BY user_id, active_on
        #{UserActivityDay::MERGE_ON_CONFLICT}
      SQL
    end

    # Ahoy visits live in their own database, so they come back to Ruby and
    # are merged in batches. Without AHOY_DB_URL there is no visit history,
    # only the visits tracked live from now on.
    def merge_visits
      return if ENV["AHOY_DB_URL"].blank?

      Ahoy::Visit.where(started_at: window).where.not(user_id: nil).distinct
        .pluck(:user_id, Arel.sql(day("started_at")))
        .each_slice(5_000) { |visits| UserActivityDay.merge_sources!(visits.map { |user_id, date| [ user_id, date, "visit" ] }) }
    end
  end
end
