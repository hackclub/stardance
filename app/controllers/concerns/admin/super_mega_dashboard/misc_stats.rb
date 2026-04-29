# frozen_string_literal: true

module Admin
  module SuperMegaDashboard
    module MiscStats
      extend ActiveSupport::Concern

      included do
        helper_method :balance_color_class
      end

      private

      def load_payouts_stats
        cached_data = Rails.cache.fetch("super_mega_payouts", expires_in: 10.minutes) do
          payouts_cap = LedgerEntry.sum(:amount)
          yesterday = 24.hours.ago
          recent = LedgerEntry.where(created_at: yesterday..)

          recent_stats = recent.pluck(
            Arel.sql("COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0)"),
            Arel.sql("COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0)"),
            Arel.sql("COUNT(*)"),
            Arel.sql("COALESCE(SUM(ABS(amount)), 0)")
          ).first

          total_distributed_cookies = LedgerEntry.where("amount > 0").sum(:amount)
          used_cookies = LedgerEntry.where("amount < 0").sum(:amount).abs
          cookie_utilization_percentage = ((used_cookies.to_f / total_distributed_cookies) * 100).round(2)

          total_approved_ysws_db_hours = fetch_approved_ysws_db_hours

          transaction_data = build_transaction_data
          hcb_expenses = transaction_data[:total_expenses]
          contractor_expenses = transaction_data[:contractor_expenses]

          if total_approved_ysws_db_hours > 0
            dollars_per_hour = (total_distributed_cookies / 5) / total_approved_ysws_db_hours
            expenses_dollars_per_hour = hcb_expenses / total_approved_ysws_db_hours
          else
            dollars_per_hour = 0
            expenses_dollars_per_hour = 0
          end

          {
            payouts_cap: payouts_cap,
            payouts: {
              created: recent_stats[0],
              destroyed: recent_stats[1],
              txns: recent_stats[2],
              volume: recent_stats[3]
            },
            cookie_utilization_percentage: cookie_utilization_percentage,
            dollars_per_hour: dollars_per_hour,
            expenses_dollars_per_hour: expenses_dollars_per_hour,
            contractor_expenses: contractor_expenses
          }
        end
        @payouts_cap = cached_data&.dig(:payouts_cap) || 0
        @payouts = cached_data&.dig(:payouts) || { created: 0, destroyed: 0, txns: 0, volume: 0 }

        @dollars_per_hour = cached_data&.dig(:dollars_per_hour) || 0
        @expenses_dollars_per_hour = cached_data&.dig(:expenses_dollars_per_hour) || 0
        @cookie_utilization_percentage = cached_data&.dig(:cookie_utilization_percentage) || 0
        @contractor_expenses = cached_data&.dig(:contractor_expenses) || 0
      rescue StandardError => e
        Rails.logger.error("[SuperMegaDashboard] Error in load_payouts_stats: #{e.class} - #{e.message}")
        @payouts_cap = 0
        @payouts = { created: 0, destroyed: 0, txns: 0, volume: 0 }
        @dollars_per_hour = 0
        @expenses_dollars_per_hour = 0
        @cookie_utilization_percentage = 0
        @contractor_expenses = 0
      end

      def load_voting_stats
        cached_data = Rails.cache.fetch("super_mega_voting", expires_in: 10.minutes) do
          today = Time.current.beginning_of_day..Time.current.end_of_day
          this_week = 7.days.ago.beginning_of_day..Time.current

          avg_columns = Vote.enabled_categories.map do |category|
            column = Vote.score_column_for!(category)
            "AVG(#{column}) AS avg_#{category}"
          end.join(", ")

          select_core = <<~SQL.squish
            COUNT(*) AS total_votes,
            COUNT(*) FILTER (WHERE created_at >= ? AND created_at <= ?) AS votes_today,
            COUNT(*) FILTER (WHERE created_at >= ?) AS votes_this_week,
            AVG(time_taken_to_vote) AS avg_time,
            COUNT(*) FILTER (WHERE repo_url_clicked = true) AS repo_clicks,
            COUNT(*) FILTER (WHERE demo_url_clicked = true) AS demo_clicks,
            COUNT(*) FILTER (WHERE reason IS NOT NULL AND reason != '') AS with_reason
          SQL
          select_sql = Vote.sanitize_sql_array([
            avg_columns.present? ? "#{select_core}, #{avg_columns}" : select_core,
            today.begin, today.end, this_week.begin
          ])

          vote_stats = Vote.select(select_sql).take
          total = vote_stats.total_votes.to_i

          voting_overview = {
            total: total,
            today: vote_stats.votes_today.to_i,
            this_week: vote_stats.votes_this_week.to_i,
            avg_time_seconds: vote_stats.avg_time&.round,
            repo_click_rate: total > 0 ? (vote_stats.repo_clicks.to_f / total * 100).round(1) : 0,
            demo_click_rate: total > 0 ? (vote_stats.demo_clicks.to_f / total * 100).round(1) : 0,
            reason_rate: total > 0 ? (vote_stats.with_reason.to_f / total * 100).round(1) : 0
          }

          voting_category_avgs = Vote.enabled_categories.index_with do |category|
            vote_stats.send(:"avg_#{category}")&.to_f&.round(2)
          end

          {
            overview: voting_overview,
            category_avgs: voting_category_avgs
          }
        end

        @voting_overview = cached_data&.dig(:overview) || {}
        @voting_category_avgs = cached_data&.dig(:category_avgs) || {}
      end

      def load_community_engagement_stats
        attendance_data = ShowAndTellAttendance.group(:date).count
        last_winner_attendance = ShowAndTellAttendance
                                   .where(winner: true)
                                   .order(date: :desc, updated_at: :desc)
                                   .includes(:project, :user)
                                   .first

        @show_and_tell_stats = {
          attendance_by_date: attendance_data,
          last_winner: last_winner_attendance
        }
      end

      def load_funnel_stats
        cached_data = Rails.cache.fetch("super_mega_funnel_stats", expires_in: 5.minutes) do
          begin
            funnel_steps = [
              "start_flow_started",
              "start_flow_name",
              "start_flow_project",
              "start_flow_devlog",
              "start_flow_signin",
              "identity_verified",
              "hackatime_linked",
              "project_created",
              "devlog_created"
            ]

            grouped_counts = FunnelEvent.where(event_name: funnel_steps)
                                         .group(:event_name)
                                         .distinct
                                         .count(:email)

            funnel_data = funnel_steps.index_with { |step| grouped_counts[step] || 0 }

            funnel_with_counts = funnel_steps.map do |step|
              count = funnel_data[step]

              {
                name: step,
                count: count
              }
            end

            { funnel_steps: funnel_with_counts }
          rescue StandardError => e
            Rails.logger.error("[SuperMegaDashboard] Error in load_funnel_stats: #{e.message}")
            { funnel_steps: [] }
          end
        end

        @funnel_steps = cached_data&.dig(:funnel_steps) || []
      end

      def load_hcb_expenses
        data = Rails.cache.fetch("super_mega_hcb_stats", expires_in: 1.hour) do
          response = Faraday.get("https://hcb.hackclub.com/api/v3/organizations/stardance")

          if response.success?
            body = JSON.parse(response.body)
            balance = body.dig("balances", "balance_cents") || 0
            total_raised = body.dig("balances", "total_raised") || 0

            {
              balance_cents: balance,
              total_raised_cents: total_raised,
              total_expenses_cents: total_raised - balance
            }
          end
        rescue StandardError => e
          { error: "Error fetching HCB stats: #{e.message}" }
        end

        @hcb_error = data[:error]
        @balance_cents = data[:balance_cents] || 0
        @total_expenses_cents = data[:total_expenses_cents] || 0
        @total_raised_cents = data[:total_raised_cents] || 0
        @hcb_spending_by_tag = fetch_hcb_spending_by_tag
      end

      def fetch_hcb_spending_by_tag
        Rails.cache.fetch("super_mega_hcb_stats_v2", expires_in: 1.hour) do
          spending_by_tag = {}
          current_page = 1

          loop do
            response = Faraday.get("https://hcb.hackclub.com/api/v3/organizations/stardance/transactions", { page: current_page, per_page: 50 })
            break unless response.success?

            data = JSON.parse(response.body)
            break if data.empty?

            data.each do |txn|
              amount = txn["amount_cents"].to_i
              next unless amount < 0

              tags = txn["tags"] || []
              tag_names = tags.map { |tag| tag["label"] }

              if tag_names.any?
                tag_names.each do |tag_name|
                  spending_by_tag[tag_name] ||= 0
                  spending_by_tag[tag_name] += amount.abs
                end
              else
                spending_by_tag["Untagged"] ||= 0
                spending_by_tag["Untagged"] += amount.abs
              end
            end

            current_page += 1
          end

          spending_by_tag.transform_values { |amount| amount / 100.0 }
        rescue StandardError => e
          Rails.logger.error("[SuperMegaDashboard] Error fetching HCB spending by tag: #{e.class} - #{e.message}")
          {}
        end
      end

      def load_flavortime_summary
        with_dashboard_timing("flavortime") do
          cached_data = Rails.cache.fetch("super_mega_flavortime_summary", expires_in: dashboard_cache_ttl(30.seconds, 2.minutes)) do
            scoped_sessions = FlavortimeSession.all

            {
              summary: {
                active_users: FlavortimeSession.active_users_count,
                total_users: FlavortimeSession.select(:user_id).distinct.count,
                total_sessions: FlavortimeSession.count,
                status_hours: (FlavortimeSession.sum(:discord_status_seconds).to_f / 3600).round(1),
                activity_chart: build_flavortime_activity_chart(scoped_sessions)
              }
            }
          end

          @flavortime_summary = empty_flavortime_summary.merge(cached_data.fetch(:summary, {}))
        end
      rescue StandardError => e
        Rails.logger.warn("[SuperMegaDashboard] Flavortime section unavailable (#{e.class}): #{e.message}")
        @flavortime_summary = empty_flavortime_summary.merge(error: "Flavortime data is temporarily unavailable")
      end

      def load_pyramid_scheme_stats
        payload = with_dashboard_timing("pyramid_scheme") do
          Rails.cache.fetch("super_mega_pyramid_scheme_stats_v2", expires_in: dashboard_cache_ttl(30.seconds, 5.minutes)) do
            PyramidReferralService.fetch_dashboard_stats
          end
        end

        if payload.blank? || payload["error"].present?
          @pyramid_scheme_stats = { error: payload&.dig("error") || "Pyramid dashboard stats are unavailable" }
          return
        end

        pending_referrals = payload.dig("referrals", "pending").to_i
        id_verified_referrals = payload.dig("referrals", "id_verified").to_i
        completed_referrals = payload.dig("referrals", "completed").to_i
        total_referrals = payload.dig("referrals", "total")
        total_referrals = pending_referrals + id_verified_referrals + completed_referrals if total_referrals.blank?

        @pyramid_scheme_stats = {
          total_hours_logged: payload.dig("activity", "total_hours_logged") || 0,
          total_referrals: total_referrals.to_i,
          completed_referrals: completed_referrals,
          verified_hours_last_week: payload.dig("activity", "verified_hours_last_week") || 0,
          verified_hours_previous_week: payload.dig("activity", "verified_hours_previous_week") || 0,
          referrals_gained_last_week: payload.dig("activity", "referrals_gained_last_week") || 0,
          referrals_gained_previous_week: payload.dig("activity", "referrals_gained_previous_week") || 0,
          partial_data: payload["partial_data"] == true,
          data_source: payload["data_source"],
          activity_timeline: payload.dig("activity", "timeline") || [],
          referral_chart: {
            labels: [ "Pending", "ID Verified", "Completed" ],
            values: [
              pending_referrals,
              id_verified_referrals,
              completed_referrals
            ]
          },
          poster_chart: {
            labels: [ "Completed Physical", "Digital", "Rejected" ],
            values: [
              payload.dig("posters", "completed_physical") || 0,
              payload.dig("posters", "completed_digital") || 0,
              payload.dig("posters", "rejected_physical") || 0
            ]
          }
        }
      rescue StandardError => e
        Rails.logger.warn("[SuperMegaDashboard] Pyramid section unavailable (#{e.class}): #{e.message}")
        @pyramid_scheme_stats = { error: "Pyramid dashboard stats are temporarily unavailable" }
      end

      def fetch_approved_ysws_db_hours
        api_key = ENV["UNIFIED_DB_INTEGRATION_AIRTABLE_KEY"]

        table = Norairrecord.table(api_key, "app3A5kJwYqxMLOgh", "YSWS Programs")
        record = table.all(filter: "{Name} = 'Stardance'").first

        weighted_total = record&.fields&.dig("Weighted–Total")

        weighted_total.to_f * 10
      rescue StandardError => e
        Rails.logger.error("[SuperMegaDashboard] Error fetching approved YSWS hours: #{e.class} - #{e.message}")
        0
      end

      def build_transaction_data
        total_expenses = 0
        contractor_expenses = 0
        current_page = 1

        loop do
          response = Faraday.get("https://hcb.hackclub.com/api/v3/organizations/stardance/transactions", { page: current_page })
          break unless response.success?

          data = JSON.parse(response.body)
          break if data.empty?

          data.each do |txn|
            amount = txn["amount_cents"].to_i
            next unless amount < 0

            has_contributor_tag = txn["tags"]&.any? do |tag|
              tag["label"] == "Contributor"
            end

            if has_contributor_tag
              contractor_expenses += amount.abs
            else
              total_expenses += amount.abs
            end
          end

          current_page += 1
        end

        {
          total_expenses: total_expenses / 100,
          contractor_expenses: contractor_expenses / 100
        }
      end

      def balance_color_class(balance_cents)
        balance_dollars = balance_cents.to_i / 100
        case balance_dollars
        when 0..1999
          "balance--red"
        when 2000..9999
          "balance--yellow"
        else
          "balance--green"
        end
      end

      def build_flavortime_activity_chart(scope)
        date_range = 13.days.ago.to_date..Time.current.to_date
        sessions_by_day = scope
          .where(created_at: date_range.first.beginning_of_day..date_range.last.end_of_day)
          .group(Arel.sql("DATE(created_at)"))
          .count
        status_hours_by_day = scope
          .where(created_at: date_range.first.beginning_of_day..date_range.last.end_of_day)
          .group(Arel.sql("DATE(created_at)"))
          .sum(:discord_status_seconds)

        {
          labels: date_range.map { |date| date.strftime("%b %-d") },
          sessions: date_range.map { |date| sessions_by_day[date] || 0 },
          status_hours: date_range.map { |date| ((status_hours_by_day[date] || 0).to_f / 3600).round(1) }
        }
      end

      def empty_flavortime_summary
        {
          active_users: 0,
          total_users: 0,
          total_sessions: 0,
          status_hours: 0,
          activity_chart: {
            labels: [],
            sessions: [],
            status_hours: []
          }
        }
      end

      def compact_flavortime_breakdown(counts, limit: 5)
        return {} if counts.blank?

        top_counts = counts.to_a.first(limit)
        remaining_count = counts.to_a.drop(limit).sum { |(_, count)| count }

        chart_data = top_counts.to_h
        chart_data["other"] = remaining_count if remaining_count.positive?
        chart_data
      end

      def chg(old, new)
        return nil if old.nil? || new.nil? || old.zero?

        ((new - old) / old.to_f * 100).round
      end

      def dashboard_cache_ttl(development_ttl, production_ttl)
        Rails.env.development? ? development_ttl : production_ttl
      end

      def with_dashboard_timing(section_name)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)
        Rails.logger.info("[SuperMegaDashboard] #{section_name} loaded in #{elapsed_ms}ms")
        result
      end
    end
  end
end
