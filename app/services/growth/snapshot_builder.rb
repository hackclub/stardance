# frozen_string_literal: true

module Growth
  # Classifies every user into a growth state for one day and the day before,
  # for every metric, and stores the counts and day-over-day transitions as
  # GrowthDailySnapshot rows. Only users who linked Hack Club Auth and are not
  # banned count: guests are deleted after 30 days and would rewrite history.
  class SnapshotBuilder
    def initialize(date)
      @date = date
    end

    def call
      counts = Hash.new { |by_metric, metric| by_metric[metric] = Hash.new { |by_prev, prev| by_prev[prev] = {} } }
      ApplicationRecord.connection.select_rows(transitions_sql).each do |metric, prev_state, state, users|
        counts[metric][prev_state][state] = users
      end

      GrowthDailySnapshot.upsert_all(
        GrowthDailySnapshot::METRICS.keys.map { |metric| row(metric, counts[metric]) },
        unique_by: [ :metric, :snapshot_on ]
      )
    end

    private

    def row(metric, transitions)
      per_state = Hash.new(0)
      transitions.each_value { |targets| targets.each { |state, users| per_state[state] += users } }

      {
        snapshot_on: @date,
        metric: metric,
        # Yesterday's state is nil only for today's new users; they are already counted.
        transitions: transitions.except(nil),
        **GrowthDailySnapshot::STATE_COLUMNS.to_h { |state, column| [ column, per_state[state] ] }
      }
    end

    def transitions_sql
      today = quote_date(@date)
      yesterday = quote_date(@date - 1)
      last_before_today = "CASE WHEN active_yesterday THEN #{yesterday} ELSE last_before_yesterday END"

      <<~SQL
        WITH metrics(metric, sources) AS (VALUES #{metric_values}),
        per_user AS (
          SELECT metrics.metric,
                 MIN(days.active_on) AS first_on,
                 BOOL_OR(days.active_on = #{today}) AS active_today,
                 BOOL_OR(days.active_on = #{yesterday}) AS active_yesterday,
                 MAX(days.active_on) FILTER (WHERE days.active_on < #{yesterday}) AS last_before_yesterday
          FROM user_activity_days days
          JOIN users ON users.id = days.user_id AND NOT users.banned
          JOIN user_identities ON user_identities.user_id = users.id AND user_identities.provider = 'hack_club'
          JOIN metrics ON days.sources && metrics.sources
          WHERE days.active_on <= #{today}
          GROUP BY metrics.metric, days.user_id
        )
        SELECT metric,
               #{state_on(yesterday, "active_yesterday", "last_before_yesterday")} AS prev_state,
               #{state_on(today, "active_today", last_before_today)} AS state,
               COUNT(*)
        FROM per_user
        GROUP BY 1, 2, 3
      SQL
    end

    # Duolingo's states: a week is the day and the six before it, a month the
    # day and the 29 before it.
    def state_on(day, active, last_before)
      <<~SQL
        CASE
          WHEN first_on > #{day} THEN NULL
          WHEN first_on = #{day} THEN 'new'
          WHEN #{active} THEN
            CASE WHEN #{last_before} >= #{day} - 6 THEN 'current'
                 WHEN #{last_before} >= #{day} - 29 THEN 'reactivated'
                 ELSE 'resurrected' END
          WHEN #{last_before} >= #{day} - 6 THEN 'at_risk_wau'
          WHEN #{last_before} >= #{day} - 29 THEN 'at_risk_mau'
          ELSE 'dormant'
        END
      SQL
    end

    def metric_values
      GrowthDailySnapshot::METRICS.map do |metric, sources|
        "(#{quote(metric)}, ARRAY[#{sources.map { |source| quote(source) }.join(", ")}]::varchar[])"
      end.join(", ")
    end

    def quote(value) = ApplicationRecord.connection.quote(value)

    def quote_date(date) = "#{quote(date)}::date"
  end
end
