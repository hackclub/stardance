# frozen_string_literal: true

module Admin
  module SuperMegaDashboard
    module FraudStats
      extend ActiveSupport::Concern

      private

      def load_fraud_stats
        cached_data = Rails.cache.fetch("super_mega_fraud_stats", expires_in: 5.minutes) do
          begin
            today = Time.current.beginning_of_day..Time.current.end_of_day

            report_counts = Project::Report.group(:status).count
            total_reports = report_counts.values.sum
            pending = report_counts["pending"] || report_counts[0] || 0
            reviewed = report_counts["reviewed"] || report_counts[1] || 0
            dismissed = report_counts["dismissed"] || report_counts[2] || 0
            new_today_reports = Project::Report.where(created_at: today).count

            fraud_reports = {
              pending: pending,
              pending_pct: total_reports > 0 ? ((pending.to_f / total_reports) * 100).round(1) : 0,
              reviewed: reviewed,
              reviewed_pct: total_reports > 0 ? ((reviewed.to_f / total_reports) * 100).round(1) : 0,
              dismissed: dismissed,
              dismissed_pct: total_reports > 0 ? ((dismissed.to_f / total_reports) * 100).round(1) : 0,
              new_today: new_today_reports
            }

            total_users = User.count
            banned = User.where(banned: true).count

            unbanned = PaperTrail::Version
              .where(item_type: "User")
              .where("object_changes ->> 'banned' IS NOT NULL")
              .where("object_changes -> 'banned' ->> 1 = ?", "false")
              .select(:item_id).distinct.count

            fraud_bans = {
              banned: banned,
              banned_pct: total_users > 0 ? ((banned.to_f / total_users) * 100).round(2) : 0,
              unbanned: unbanned,
              ban_unban_ratio: total_users > 0 ? ((banned.to_f / total_users) * 100).round(1) : 0
            }

            # Second chances vs bans (ban changes today)
            bans_today = PaperTrail::Version.where(item_type: "User", created_at: today)
                                            .where("object_changes ->> 'banned' IS NOT NULL")
                                            .where("object_changes -> 'banned' ->> 1 = ?", "true").count
            unbans_today = PaperTrail::Version.where(item_type: "User", created_at: today)
                                              .where("object_changes ->> 'banned' IS NOT NULL")
                                              .where("object_changes -> 'banned' ->> 1 = ?", "false").count

            fraud_second_chances = {
              bans_today: bans_today,
              unbans_today: unbans_today,
              net_change: bans_today - unbans_today
            }

            # Fraud dept only handles: pending, awaiting_verification, on_hold, rejected
            fraud_order_counts = ShopOrder.where(aasm_state: %w[pending awaiting_verification on_hold rejected])
                                          .group(:aasm_state).count
            pending = fraud_order_counts["pending"] || 0
            awaiting_verification = fraud_order_counts["awaiting_verification"] || 0
            total_fraud_orders = fraud_order_counts.values.sum
            backlog = pending + awaiting_verification
            on_hold = fraud_order_counts["on_hold"] || 0
            rejected = fraud_order_counts["rejected"] || 0
            new_today_orders = ShopOrder.where(aasm_state: %w[pending awaiting_verification on_hold rejected], created_at: today).count

            fraud_orders = {
              pending: pending,
              pending_pct: backlog > 0 ? ((pending.to_f / backlog) * 100).round(1) : 0,
              awaiting: awaiting_verification,
              awaiting_pct: backlog > 0 ? ((awaiting_verification.to_f / backlog) * 100).round(1) : 0,
              on_hold: on_hold,
              rejected: rejected,
              backlog: backlog,
              backlog_pct: total_fraud_orders > 0 ? ((backlog.to_f / total_fraud_orders) * 100).round(1) : 0,
              new_today: new_today_orders
            }

            {
              fraud_reports: fraud_reports,
              fraud_bans: fraud_bans,
              fraud_second_chances: fraud_second_chances,
              fraud_orders: fraud_orders,
              joe_fraud_stats: fetch_joe_fraud_stats,
              fraud_ban_trend_data: build_ban_trend_data,
              fraud_shop_order_trend_data: build_shop_order_trend_data,
              fraud_report_trend_data: build_report_trend_data
            }
          rescue StandardError => e
            Rails.logger.error("[SuperMegaDashboard] Error in load_fraud_stats: #{e.message}")
            {
              fraud_reports: {},
              fraud_bans: {},
              fraud_second_chances: {},
              fraud_orders: {},
              joe_fraud_stats: { error: "Joe error" },
              fraud_ban_trend_data: {},
              fraud_shop_order_trend_data: {},
              fraud_report_trend_data: {}
            }
          end
        end

        @fraud_reports = cached_data&.dig(:fraud_reports) || {}
        @fraud_bans = cached_data&.dig(:fraud_bans) || {}
        @fraud_second_chances = cached_data&.dig(:fraud_second_chances) || {}
        @fraud_orders = cached_data&.dig(:fraud_orders) || {}
        @joe_fraud_stats = cached_data&.dig(:joe_fraud_stats) || {}
        @fraud_ban_trend_data = cached_data&.dig(:fraud_ban_trend_data) || {}
        @fraud_shop_order_trend_data = cached_data&.dig(:fraud_shop_order_trend_data) || {}
        @fraud_report_trend_data = cached_data&.dig(:fraud_report_trend_data) || {}
      end

      def build_ban_trend_data
        Rails.cache.fetch("super_mega_ban_trend", expires_in: 1.hour) do
          window_start = 29.days.ago.beginning_of_day
          window_end = Time.current.end_of_day

          base_scope = PaperTrail::Version.where(item_type: "User", created_at: window_start..window_end)

          bans_by_date = base_scope
            .where("object_changes ->> 'banned' IS NOT NULL")
            .where("object_changes -> 'banned' ->> 1 = ?", "true")
            .group(Arel.sql("DATE(created_at)")).count

          unbans_by_date = base_scope
            .where("object_changes ->> 'banned' IS NOT NULL")
            .where("object_changes -> 'banned' ->> 1 = ?", "false")
            .group(Arel.sql("DATE(created_at)")).count

          (0..29).reverse_each.each_with_object({}) do |days_ago, trend_data|
            date = days_ago.days.ago.to_date
            trend_data[date.to_s] = {
              bans: bans_by_date[date] || 0,
              unbans: unbans_by_date[date] || 0
            }
          end
        end
      end

      def build_shop_order_trend_data
        Rails.cache.fetch("super_mega_order_trend", expires_in: 1.hour) do
          window_start = 29.days.ago.beginning_of_day
          window_end = Time.current.end_of_day
          states = %w[pending awaiting_verification rejected on_hold]

          grouped = ShopOrder.where(updated_at: window_start..window_end, aasm_state: states)
                             .group(Arel.sql("DATE(updated_at)"), :aasm_state).count

          (0..29).reverse_each.each_with_object({}) do |days_ago, trend_data|
            date = days_ago.days.ago.to_date
            day_counts = {}
            states.each { |s| day_counts[s] = grouped.fetch([ date, s ], 0) }
            trend_data[date.to_s] = day_counts
          end
        end
      end

      def build_report_trend_data
        Rails.cache.fetch("super_mega_report_trend", expires_in: 1.hour) do
          window_start = 29.days.ago.beginning_of_day
          window_end = Time.current.end_of_day

          grouped = Project::Report.where(updated_at: window_start..window_end)
                                   .group(Arel.sql("DATE(updated_at)"), :reason).count

          (0..29).reverse_each.each_with_object({}) do |days_ago, trend_data|
            date = days_ago.days.ago.to_date
            day_counts = {}
            grouped.each do |(d, reason), count|
              day_counts[reason] = count if d == date
            end
            trend_data[date.to_s] = day_counts
          end
        end
      end

      def calculate_review_quality
        reviewed_reports = Project::Report.where(status: %w[reviewed dismissed])
                                          .pluck(:created_at, :updated_at)

        if reviewed_reports.any?
          avg_review_hours = reviewed_reports.map { |(created, updated)| ((updated - created) / 1.hour).round(1) }.sum / reviewed_reports.count
        else
          avg_review_hours = 0
        end

        total_reviewed = Project::Report.where(status: %w[reviewed dismissed]).count
        this_week_reviewed = Project::Report.where(status: %w[reviewed dismissed], updated_at: 7.days.ago..).count

        {
          total_reviewed: total_reviewed,
          avg_review_hours: avg_review_hours.round(1),
          this_week: this_week_reviewed
        }
      end

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

          response = conn.get("https://joe.fraud.hackclub.com/api/v1/cases/dashboard?range=30d&ysws=Flavortown") do |req|
            req.headers["Cookie"] = api_key
          end

          unless response.success?
            return { error: "API returned #{response.status}" }
          end

          data = JSON.parse(response.body, symbolize_names: true)

          kpis = data[:kpis] || {}
          charts = data[:charts] || {}

          {
            total: data[:total] || kpis[:totalCases] || 0,
            open: data[:open] || kpis[:openCount] || 0,
            waiting: kpis[:waitingCount] || 0,
            closed: data[:closed] || kpis[:closedCount] || 0,
            avg_hang_time_days: kpis[:avgHangTimeDays]&.to_f || 0,
            second_chances_given: data.dig(:byStatus, :second_chance_given) || charts[:byStatus]&.find { |s| s[:status] == "second_chance_given" }&.dig(:count) || 0,
            fraudpheus_open: data.dig(:byStatus, :fraudpheus_open) || charts[:byStatus]&.find { |s| s[:status] == "fraudpheus_open" }&.dig(:count) || 0,
            created_over_time: charts[:createdOverTime] || [],
            longest_hang_times: data[:longestHangTimes] || [],
            stalest_case: data[:stalestCase],
            timeline: data[:timeline] || [],
            cases_opened: data[:casesOpened] || []
          }
        end
      rescue Faraday::Error
        { error: "Couldn't reach the API" }
      rescue JSON::ParserError
        { error: "Got a weird response" }
      end

      def load_fraud_happiness_data
        data = FraudAirtableService.fetch_fraud_happy_by_week || {}
        @fraud_happiness_week = data[:week]
        @fraud_happiness_records = data[:records] || []
        @fraud_happiness_avg_scores = data[:avg_scores] || { total_responses: 0 }
        @fraud_happiness_error = data[:error]
        @fraud_vibes_history = FraudAirtableService.fetch_vibes_history || {}

        if @fraud_happiness_week.present? && @fraud_vibes_history.present?
          sorted_weeks = @fraud_vibes_history.keys.map(&:to_s).sort_by { |w| w.scan(/\d+/).first.to_i }
          current_idx = sorted_weeks.index(@fraud_happiness_week.to_s)
          prev_week = (current_idx && current_idx > 0) ? sorted_weeks[current_idx - 1] : nil
          @fraud_happiness_prev_scores = prev_week ? @fraud_vibes_history[prev_week] : nil
        end
      end
    end
  end
end
