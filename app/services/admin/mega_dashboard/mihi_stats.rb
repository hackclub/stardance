module Admin
  module MegaDashboard
    class MihiStats
      def initialize(period: QueueStats::DEFAULT_PERIOD, now: Time.current)
        @days = QueueStats::PERIODS.fetch(period.to_s, QueueStats::PERIODS.fetch(QueueStats::DEFAULT_PERIOD))
        @today = now.in_time_zone("America/New_York").to_date
      end

      def to_h
        dates = (@today - (@days - 1))..@today
        activations = MihiActivation.where(activated_on: dates)
        counts = activations.group(:activated_on).count
        totals = activations.group(:activated_on).sum(:activations_count)
        {
          today: counts.fetch(@today, 0),
          unique_users: activations.distinct.count(:user_id),
          total: totals.values.sum,
          daily: dates.to_h { |date| [ date.iso8601, counts.fetch(date, 0) ] },
          daily_totals: dates.to_h { |date| [ date.iso8601, totals.fetch(date, 0) ] }
        }
      end
    end
  end
end
