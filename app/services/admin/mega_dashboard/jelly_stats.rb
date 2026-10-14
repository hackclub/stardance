module Admin
  module MegaDashboard
    # Support queue stats, read entirely from the local mirror that
    # JellySyncJob maintains. Nothing here calls the Jelly API: a panel render
    # must never cost hundreds of requests, and the daily series only exists
    # locally because Jelly has no historical endpoint.
    class JellyStats
      PERIODS = QueueStats::PERIODS

      def initialize(period: QueueStats::DEFAULT_PERIOD, now: Time.current)
        @period = PERIODS.key?(period.to_s) ? period.to_s : QueueStats::DEFAULT_PERIOD
        @now = now
      end

      def to_h
        {
          configured: ::Jelly::Client.configured?,
          stale: ::JellyConversation.stale?,
          last_synced_at: ::JellyConversation.last_synced_at,
          period: @period,
          tiles: tiles,
          chart_data: chart_data,
          history_days: daily_stats.size
        }
      end

      private

      def window_start = (@now - (PERIODS.fetch(@period) - 1).days).beginning_of_day

      def daily_stats = @daily_stats ||= ::JellyDailyStat.since(window_start.to_date).to_a

      def tiles
        open_conversations = ::JellyConversation.open_now
        responses = ::JellyConversation.where(opened_at: window_start..)
                                       .where.not(first_response_seconds: nil)
                                       .pluck(:first_response_seconds)

        {
          arrivals: ::JellyConversation.where(opened_at: window_start..).count,
          open: open_conversations.count,
          awaiting_reply: ::JellyConversation.awaiting_reply.count,
          median_first_response_hours: percentile_hours(responses, 50),
          response_sample: responses.size
        }
      end

      def chart_data
        daily_stats.map do |stat|
          {
            date: stat.recorded_on.strftime("%-d %b"),
            arrived: stat.arrivals.to_i,
            decided: stat.resolutions.to_i,
            latency_hours: stat.median_first_response_seconds ? (stat.median_first_response_seconds / 3600.0).round(1) : nil,
            backlog: stat.awaiting_reply_count.to_i
          }
        end
      end

      def percentile_hours(seconds, percentile)
        return if seconds.blank?

        sorted = seconds.compact.sort
        (sorted[((percentile / 100.0) * (sorted.size - 1)).round] / 3600.0).round(1)
      end
    end
  end
end
