module Admin
  class FraudDashboardController < ApplicationController
    def index
      authorize :admin, :access_fraud_dashboard?
      today = Time.current.beginning_of_day..Time.current.end_of_day

      # Single query for all report stats
      report_stats_sql = Project::Report.sanitize_sql_array([
        "SELECT COUNT(*) FILTER (WHERE status = 0) AS pending_count,
                COUNT(*) FILTER (WHERE status = 1) AS reviewed_count,
                COUNT(*) FILTER (WHERE status = 2) AS dismissed_count,
                COUNT(*) FILTER (WHERE created_at >= ? AND created_at <= ?) AS new_today
         FROM project_reports", today.begin, today.end
      ])
      rs = ActiveRecord::Base.connection.select_one(report_stats_sql)

      reasons = Project::Report.group(:reason).count

      @reports = {
        pending: rs["pending_count"].to_i,
        reviewed: rs["reviewed_count"].to_i,
        dismissed: rs["dismissed_count"].to_i,
        new_today: rs["new_today"].to_i,
        reasons: reasons,
        by_status: { pending: rs["pending_count"].to_i, reviewed: rs["reviewed_count"].to_i, dismissed: rs["dismissed_count"].to_i },
        top_reviewers: all_time_report_performers(%w[reviewed dismissed]),
        avg_response_hours: avg_response("project_reports", "Project::Report", "status", %w[reviewed dismissed])
      }

      # Single query for ban stats
      ban_stats_sql = <<~SQL
        SELECT
          COUNT(*) FILTER (WHERE banned = true) AS banned_count
        FROM users
        WHERE banned = true
      SQL
      bs = ActiveRecord::Base.connection.select_one(ban_stats_sql)

      # Single query for all version-based ban changes today
      ban_changes = batch_changes_count(today)

      @bans = {
        banned: bs["banned_count"].to_i,
        bans_today: ban_changes.dig("User", "banned", "true") || 0,
        unbans_today: ban_changes.dig("User", "banned", "false") || 0
      }

      # Single query for order stats
      order_stats_sql = Project::Report.sanitize_sql_array([
        "SELECT COUNT(*) FILTER (WHERE aasm_state = 'pending') AS pending_count,
                COUNT(*) FILTER (WHERE aasm_state = 'on_hold') AS on_hold_count,
                COUNT(*) FILTER (WHERE aasm_state = 'rejected') AS rejected_count,
                COUNT(*) FILTER (WHERE aasm_state = 'awaiting_periodical_fulfillment') AS awaiting_count,
                COUNT(*) FILTER (WHERE created_at >= ? AND created_at <= ?) AS new_today
         FROM shop_orders", today.begin, today.end
      ])
      os = ActiveRecord::Base.connection.select_one(order_stats_sql)

      order_states = %w[awaiting_periodical_fulfillment rejected on_hold fulfilled]

      @orders = {
        pending: os["pending_count"].to_i,
        on_hold: os["on_hold_count"].to_i,
        rejected: os["rejected_count"].to_i,
        awaiting: os["awaiting_count"].to_i,
        backlog: os["pending_count"].to_i + os["awaiting_count"].to_i,
        new_today: os["new_today"].to_i,
        top_reviewers: all_time_performers(order_states),
        avg_response_hours: avg_response("shop_orders", "ShopOrder", "aasm_state", %w[awaiting_periodical_fulfillment rejected fulfilled])
      }

      # Fetch Joe fraud case stats with timeline
      @joe_fraud_stats = fetch_joe_fraud_stats

      # Build trend data for charts
      @fraud_shop_order_trend_data = build_shop_order_trend_data
      @fraud_report_trend_data = build_report_trend_data
      @fraud_report_status_trend_data = build_report_status_trend_data
    end

    private

    def fetch_joe_fraud_stats
      Rails.cache.fetch("joe_fraud_stats", expires_in: 5.minutes) do
        api_key = ENV["NEONS_JOE_COOKIES"]
        unless api_key.present?
          return { error: "NEONS_JOE_COOKIES not configured" }
        end

        conn = Faraday.new do |f|
          f.options.timeout = 10
          f.options.open_timeout = 5
        end

        response = conn.get("https://joe.fraud.hackclub.com/api/v1/cases/stats?ysws=flavortown") do |req|
          req.headers["Cookie"] = api_key
        end

        unless response.success?
          return { error: "API returned #{response.status}" }
        end

        data = JSON.parse(response.body, symbolize_names: true)

        {
          total: data[:total],
          open: data[:open],
          closed: data[:closed],
          second_chances_given: data.dig(:byStatus, :second_chance_given) || 0,
          fraudpheus_open: data.dig(:byStatus, :fraudpheus_open) || 0,
          timeline: data[:timeline] || [],
          cases_opened: data[:casesOpened] || []
        }
      end
    rescue Faraday::Error
      { error: "Couldn't reach the API" }
    rescue JSON::ParserError
      { error: "Got a weird response" }
    end

    private

    def batch_changes_count(today)
      sql = PaperTrail::Version.sanitize_sql_array([
        "SELECT item_type,
                'banned' AS field,
                object_changes -> 'banned' ->> 1 AS new_value,
                COUNT(*) AS cnt
         FROM versions
         WHERE item_type IN ('User', 'Project')
           AND created_at >= ? AND created_at <= ?
           AND jsonb_exists(object_changes, 'banned')
         GROUP BY item_type, field, new_value",
        today.begin, today.end
      ])

      result = {}
      ActiveRecord::Base.connection.select_all(sql).each do |row|
        result[row["item_type"]] ||= {}
        result[row["item_type"]][row["field"]] ||= {}
        result[row["item_type"]][row["field"]][row["new_value"]] = row["cnt"].to_i
      end
      result
    end

    def all_time_performers(states)
      pg_array = "{#{states.join(',')}}"
      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, pg_array ])
        SELECT whodunnit, COUNT(*) AS cnt
        FROM versions
        WHERE item_type = 'ShopOrder'
          AND whodunnit IS NOT NULL
          AND jsonb_exists(object_changes, 'aasm_state')
          AND (object_changes -> 'aasm_state' ->> 1) = ANY (?::text[])
        GROUP BY whodunnit
        ORDER BY cnt DESC
        LIMIT 10
      SQL

      rows = ActiveRecord::Base.connection.select_all(sql).to_a
      ids = rows.map { |r| r["whodunnit"].to_i }
      return [] if ids.empty?

      users = User.where(id: ids).select(:id, :display_name).index_by(&:id)
      rows.map { |r| { name: users[r["whodunnit"].to_i]&.display_name || "User ##{r["whodunnit"]}", count: r["cnt"].to_i } }
    end

    def all_time_report_performers(states)
      pg_array = "{#{states.join(',')}}"
      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, pg_array ])
        SELECT whodunnit, COUNT(*) AS cnt
        FROM versions
        WHERE item_type = 'Project::Report'
          AND whodunnit IS NOT NULL
          AND jsonb_exists(object_changes, 'status')
          AND (object_changes -> 'status' ->> 1) = ANY (?::text[])
        GROUP BY whodunnit
        ORDER BY cnt DESC
        LIMIT 10
      SQL

      rows = ActiveRecord::Base.connection.select_all(sql).to_a
      ids = rows.map { |r| r["whodunnit"].to_i }
      return [] if ids.empty?

      users = User.where(id: ids).select(:id, :display_name).index_by(&:id)
      rows.map { |r| { name: users[r["whodunnit"].to_i]&.display_name || "User ##{r["whodunnit"]}", count: r["cnt"].to_i } }
    end

    TABLES = %w[project_reports shop_orders].freeze
    FIELDS = %w[status aasm_state].freeze
    TYPES = %w[Project::Report ShopOrder].freeze

    def avg_response(table, type, field, states)
      raise ArgumentError unless TABLES.include?(table) && FIELDS.include?(field) && TYPES.include?(type)
      quoted_table = ActiveRecord::Base.connection.quote_table_name(table)
      quoted_field = ActiveRecord::Base.connection.quote_column_name(field)

      db_values = if table == "project_reports" && field == "status"
                    states.map { |s| Project::Report.statuses.fetch(s) }
      else
                    states
      end

      record_cast = (table == "project_reports" && field == "status") ? "int[]" : "text[]"
      record_pg_array = "{#{db_values.join(',')}}"
      version_pg_array = "{#{db_values.map(&:to_s).join(',')}}"

      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, record_pg_array, type, field, field, version_pg_array ])
        SELECT AVG(EXTRACT(EPOCH FROM (v.v_at - r.r_at)) / 3600.0) AS avg_hours
        FROM (
          SELECT r.id, r.created_at AS r_at
          FROM #{quoted_table} r
          WHERE r.#{quoted_field} = ANY (?::#{record_cast})
            AND r.created_at > NOW() - INTERVAL '30 days'
          ORDER BY r.created_at DESC
          LIMIT 100
        ) r
        JOIN LATERAL (
          SELECT v.created_at AS v_at
          FROM versions v
          WHERE v.item_type = ?
            AND v.item_id = r.id::text
            AND jsonb_exists(v.object_changes, ?)
            AND v.created_at >= r.r_at
            AND (v.object_changes -> ? ->> 1) = ANY (?::text[])
          ORDER BY v.created_at ASC
          LIMIT 1
        ) v ON true
      SQL
      ActiveRecord::Base.connection.select_one(sql)&.dig("avg_hours")&.to_f&.round(1)
      end

      def build_shop_order_trend_data
      trend_data = {}
      # Get data for last 60 days
      (0..59).reverse_each do |days_ago|
        date = days_ago.days.ago.to_date
        day_range = date.beginning_of_day..date.end_of_day

        # Count shop orders by state on this day
        states = %w[pending awaiting_periodical_fulfillment fulfilled rejected on_hold]
        state_counts = ShopOrder.where(updated_at: day_range)
                                .where(aasm_state: states)
                                .group(:aasm_state).count

        trend_data[date.to_s] = state_counts.transform_keys(&:to_s)
      end
      trend_data
      end

      def build_report_trend_data
      trend_data = {}
      # Get data for last 60 days
      (0..59).reverse_each do |days_ago|
        date = days_ago.days.ago.to_date
        day_range = date.beginning_of_day..date.end_of_day

        # Count fraud reports by reason on this day
        reason_counts = Project::Report.where(updated_at: day_range)
                                       .group(:reason).count

        trend_data[date.to_s] = reason_counts
      end
      trend_data
      end

      def build_report_status_trend_data
      trend_data = {}
      # Get data for last 60 days
      (0..59).reverse_each do |days_ago|
        date = days_ago.days.ago.to_date
        day_range = date.beginning_of_day..date.end_of_day

        # Count fraud reports by status on this day
        status_counts = Project::Report.where(updated_at: day_range)
                                       .group(:status).count

        # Convert integer statuses to string names
        status_map = { 0 => "pending", 1 => "reviewed", 2 => "dismissed" }
        trend_data[date.to_s] = status_counts.transform_keys { |k| status_map[k] || k.to_s }
      end
      trend_data
      end
  end
end
