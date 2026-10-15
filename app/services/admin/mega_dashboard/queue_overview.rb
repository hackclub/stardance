module Admin
  module MegaDashboard
    # The at-a-glance table above the sections: one row per queue, always over
    # a fixed 7 day window so the flow columns stay comparable no matter which
    # period the panels below are showing.
    class QueueOverview
      OVERVIEW_PERIOD = "7"

      Row = Data.define(:queue, :stats, :error) do
        def label = queue.label
        def url = queue.url
        def depth = stats&.tiles&.dig(:depth) || 0
        def median_decision_hours = stats&.tiles&.dig(:median_decision_hours)
        def arrivals = stats&.tiles&.dig(:arrivals) || 0
        def decisions = stats&.metrics&.dig(:decisions) || 0
        def net = stats&.metrics&.dig(:net) || 0
        def days_to_clear = stats&.metrics&.dig(:days_to_clear)
        def oldest_wait_hours = stats&.metrics&.dig(:oldest_wait_hours)
        def overdue = stats&.metrics&.dig(:overdue) || 0

        # Drives the row's colour. Overdue work outranks flow, since a queue
        # can be clearing faster than it fills and still be sitting on
        # something that blew its SLA a week ago.
        def health
          return "error" if error
          return "empty" if depth.zero?
          return "behind" if overdue.positive?
          return "growing" if net.positive?

          "ok"
        end
      end

      # A queue that can't be read (a missing column, a renamed scope) becomes
      # one error row rather than taking the whole table down with it.
      def self.rows(now: Time.current)
        Queue.all.map do |queue|
          begin
            Row.new(queue: queue, stats: QueueStats.new(queue, period: OVERVIEW_PERIOD, now: now), error: nil)
          rescue StandardError => e
            Rails.logger.error("[MegaDashboard] queue #{queue.key} failed (#{e.class}): #{e.message}")
            Row.new(queue: queue, stats: nil, error: e.message)
          end
        end
      end

      def self.totals(rows)
        {
          depth: rows.sum(&:depth),
          overdue: rows.sum(&:overdue),
          behind: rows.count { |row| row.health == "behind" },
          growing: rows.count { |row| row.health == "growing" },
          errored: rows.count { |row| row.health == "error" }
        }
      end
    end
  end
end
