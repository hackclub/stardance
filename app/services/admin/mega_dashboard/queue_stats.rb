module Admin
  module MegaDashboard
    # Period-scoped stats for a single review queue, shaped for the shared
    # queue panel: four headline tiles and three daily series.
    #
    # Every series is folded in Ruby out of one entered/decided pluck rather
    # than queried per day, so a 90 day window costs the same round trips as a
    # 7 day one.
    class QueueStats
      PERIODS = { "7" => 7, "30" => 30, "90" => 90 }.freeze
      DEFAULT_PERIOD = "30"

      attr_reader :queue

      def initialize(queue, period: DEFAULT_PERIOD, now: Time.current)
        @queue = queue
        @period = PERIODS.key?(period.to_s) ? period.to_s : DEFAULT_PERIOD
        @period_days = PERIODS.fetch(@period)
        @now = now
        @pairs = queue.timestamp_pairs(window_start)
      end

      def tiles
        {
          arrivals: arrivals_in_period.size,
          depth: open_waits.size,
          median_decision_hours: percentile_hours(decided_latencies, 50),
          decided_sample: decided_latencies.size
        }
      end

      def metrics
        {
          decisions: decided_in_period.size,
          p90_decision_hours: percentile_hours(decided_latencies, 90),
          oldest_wait_hours: open_waits.map { |wait| wait / 3600.0 }.max&.round(1),
          overdue: open_waits.count { |wait| wait > queue.sla_hours.hours },
          # A fixed cross-queue ageing line, independent of each queue's own SLA,
          # so the panels can be compared against one another.
          over_three_days: open_waits.count { |wait| wait > 3.days },
          sla_hours: queue.sla_hours,
          # Net is the change in the pool, so it reads the way the queue feels:
          # positive when more arrives than leaves, negative when it drains.
          net: arrivals_in_period.size - decided_in_period.size,
          decisions_per_day: (decided_in_period.size / @period_days.to_f).round(1),
          arrivals_per_day: (arrivals_in_period.size / @period_days.to_f).round(1),
          net_per_day: ((arrivals_in_period.size - decided_in_period.size) / @period_days.to_f).round(1),
          days_to_clear: days_to_clear
        }
      end

      # One row per day: arrivals and decisions (paired bars), median decision
      # latency, and the backlog as it stood at end of day.
      def chart_data
        dates.map do |date|
          day_end = date.in_time_zone.end_of_day
          settled_today = @pairs.filter_map do |entered, decided|
            span = (decided - entered) if decided&.to_date == date && entered
            span if span&.positive?
          end

          {
            date: date.strftime("%-d %b"),
            arrived: @pairs.count { |entered, _| entered&.to_date == date },
            decided: @pairs.count { |_, decided| decided&.to_date == date },
            latency_hours: percentile_hours(settled_today, 50),
            backlog: @pairs.count { |entered, decided| entered && entered <= day_end && (decided.nil? || decided > day_end) }
          }
        end
      end

      private

      def window_start = (@now - (@period_days - 1).days).beginning_of_day

      def dates = (window_start.to_date..@now.to_date).to_a

      # How long each item currently in the queue has been waiting. Comes from
      # the queue's own pending relation, so depth and ageing always agree with
      # the review page the panel links to; the entered/decided pairs below
      # only drive the historical series.
      def open_waits = @open_waits ||= queue.open_entered_ats.map { |entered| @now - entered }

      def arrivals_in_period = @pairs.select { |entered, _| entered && entered >= window_start }

      def decided_in_period = @pairs.select { |_, decided| decided && decided >= window_start }

      # Latency only counts items decided inside the window, so the number
      # tracks current turnaround instead of drifting with all-time history.
      # Negative spans are dropped rather than averaged in: a decided_at older
      # than its entered_at is bad data (backfills and state machines that
      # stamp out of order both produce it), and one of them can drag a median
      # below zero.
      def decided_latencies
        @decided_latencies ||= decided_in_period.filter_map do |entered, decided|
          span = (decided - entered) if entered
          span if span&.positive?
        end
      end

      # Separate from `net`: this needs the drain rate, which is the opposite
      # sign, and only exists when the queue is actually shrinking.
      def days_to_clear
        drain_per_day = (decided_in_period.size - arrivals_in_period.size) / @period_days.to_f
        return if drain_per_day <= 0 || open_waits.empty?

        (open_waits.size / drain_per_day).round(1)
      end

      def percentile_hours(seconds, percentile)
        return if seconds.blank?

        sorted = seconds.sort
        index = ((percentile / 100.0) * (sorted.size - 1)).round
        (sorted[index] / 3600.0).round(1)
      end
    end
  end
end
