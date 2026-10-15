module Admin
  module MegaDashboard
    # The voting queue seen from the voter's side: assignments handed out,
    # what happened to them, and how long a vote takes.
    #
    # The ship's side of the same queue (how long a ship waits for its votes)
    # is the Rating Hangtime dashboard, so this panel deliberately doesn't
    # restate it beyond the one number that turns the backlog into an action:
    # how many more votes are needed to clear it.
    class VoteStats
      PERIODS = QueueStats::PERIODS

      def initialize(period: QueueStats::DEFAULT_PERIOD, now: Time.current)
        @period = PERIODS.key?(period.to_s) ? period.to_s : QueueStats::DEFAULT_PERIOD
        @now = now
      end

      def to_h
        {
          period: @period,
          tiles: tiles,
          quality: quality,
          category_averages: category_averages,
          chart_data: chart_data
        }
      end

      private

      def period_days = PERIODS.fetch(@period)

      def window_start = (@now - (period_days - 1).days).beginning_of_day

      def votes_in_period = ::Vote.where(created_at: window_start..)

      def assignments_in_period = ::Vote::Assignment.where(created_at: window_start..)

      def tiles
        durations = votes_in_period.where.not(time_taken_to_vote_in_seconds: nil)
                                   .pluck(:time_taken_to_vote_in_seconds)
        cast = votes_in_period.count
        deficits = deficit_by_date.values

        {
          votes: cast,
          active_voters: votes_in_period.distinct.count(:user_id),
          median_time_to_vote_minutes: percentile_minutes(durations, 50),
          p95_time_to_vote_minutes: percentile_minutes(durations, 95),
          outstanding_assignments: ::Vote::Assignment.where(status: "assigned").count,
          votes_needed_to_clear: votes_needed_to_clear,
          cast_per_day: (cast / period_days.to_f).round(1),
          # Change in votes owed, matching the queues' convention: positive when
          # the pool grows, negative when voters are burning it down.
          net_per_day: deficits.size < 2 ? nil : ((deficits.last - deficits.first) / period_days.to_f).round(1),
          median_rating_hours: median_rating_hours
        }
      end

      # How long a ship spends in the rating stage end to end. Backfilled
      # estimates are excluded for the same reason the waterfall excludes them.
      def median_rating_hours
        spans = ::Post::ShipEvent
          .where.not(voting_started_at: nil).where(voting_completed_at: window_start..)
          .where(lifecycle_data_quality: %w[live backfilled_exact])
          .pluck(:voting_started_at, :voting_completed_at)
          .filter_map { |started, completed| (completed - started) if completed && started && completed > started }

        return if spans.empty?

        (spans.sort[(spans.size - 1) / 2] / 3600.0).round(1)
      end

      # The backlog expressed as work rather than as a count of ships: sum of
      # the votes each waiting ship still needs. This is the number that says
      # whether the voting pool can actually clear the queue.
      def votes_needed_to_clear
        required = ::Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT
        counts = ::Vote.payout_countable
                       .where(ship_event_id: ::Post::ShipEvent.voteable.select(:id))
                       .group(:ship_event_id).count

        ::Post::ShipEvent.voteable.pluck(:id).sum do |id|
          [ required - counts.fetch(id, 0), 0 ].max
        end
      end

      def quality
        total = votes_in_period.count
        return {} if total.zero?

        counts = votes_in_period.pick(
          Arel.sql("COUNT(*) FILTER (WHERE repo_opened)"),
          Arel.sql("COUNT(*) FILTER (WHERE demo_opened)"),
          Arel.sql("COUNT(*) FILTER (WHERE reason IS NOT NULL AND reason <> '')"),
          Arel.sql("COUNT(*) FILTER (WHERE discarded)")
        )

        assignments = assignments_in_period.group(:status).count
        handled = assignments.values.sum

        {
          repo_opened_rate: percent(counts[0], total),
          demo_opened_rate: percent(counts[1], total),
          reason_rate: percent(counts[2], total),
          discarded_rate: percent(counts[3], total),
          skip_rate: percent(assignments["skipped"], handled),
          expiry_rate: percent(assignments["expired"], handled),
          # An assignment opened and then abandoned reads very differently from
          # one that was never looked at, so they're counted apart.
          never_viewed: assignments_in_period.where(status: %w[skipped expired], first_viewed_at: nil).count
        }
      end

      def category_averages
        ::Vote::SCORE_COLUMNS_BY_CATEGORY.transform_values do |column|
          votes_in_period.average(column)&.to_f&.round(2)
        end
      end

      def chart_data
        votes_by_date = votes_in_period.group(Arel.sql("DATE(votes.created_at)")).count
        assigned_by_date = assignments_in_period.group(Arel.sql("DATE(vote_assignments.created_at)")).count
        rating_by_date = rating_spans_by_completion_date
        deficits = deficit_by_date

        (window_start.to_date..@now.to_date).map do |date|
          spans = rating_by_date.fetch(date, [])

          {
            date: date.strftime("%-d %b"),
            arrived: assigned_by_date.fetch(date, 0),
            decided: votes_by_date.fetch(date, 0),
            latency_hours: spans.empty? ? nil : (spans.sort[(spans.size - 1) / 2] / 3600.0).round(1),
            backlog: deficits.fetch(date, 0)
          }
        end
      end

      # The voting backlog isn't a count of items, it's a count of votes still
      # owed: summed across every ship in the pool that day, how far short of
      # the payout threshold it was. That is the same shape as the other
      # queues' backlog series, just measured in votes rather than rows.
      def deficit_by_date
        # Approved and unpaid only: a ship that was paid or rejected has left
        # the pool, and counting it forever made the deficit look like it only
        # ever climbed.
        ships = ::Post::ShipEvent.approved.where.not(voting_started_at: nil)
                                 .pluck(:id, :voting_started_at, :voting_completed_at, :paid_at)
        return {} if ships.empty?

        votes_by_ship = ::Vote.payout_countable
                              .where(ship_event_id: ships.map(&:first))
                              .pluck(:ship_event_id, :created_at)
                              .group_by(&:first)
                              .transform_values { |rows| rows.map(&:last).sort }

        required = ::Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT

        (window_start.to_date..@now.to_date).index_with do |date|
          day_end = date.in_time_zone.end_of_day

          ships.sum do |id, started_at, completed_at, paid_at|
            next 0 if started_at > day_end
            next 0 if completed_at && completed_at <= day_end
            next 0 if paid_at && paid_at <= day_end

            # bsearch_index finds the first vote after the cutoff, which is the
            # count of votes cast on or before it.
            cast = votes_by_ship[id] || []
            counted = cast.bsearch_index { |at| at > day_end } || cast.size
            [ required - counted, 0 ].max
          end
        end
      end

      def percent(count, total)
        return if total.nil? || total.zero?

        ((count.to_i * 100.0) / total).round(1)
      end

      # Voting takes minutes, not hours, so this panel's latency series is in
      # minutes. The shared chart labels it accordingly.
      # Rating spans keyed by the day the ship reached the vote threshold.
      def rating_spans_by_completion_date
        ::Post::ShipEvent
          .where(voting_completed_at: window_start..)
          .where.not(voting_started_at: nil)
          .where(lifecycle_data_quality: %w[live backfilled_exact])
          .pluck(:voting_started_at, :voting_completed_at)
          .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(started, completed), acc|
            acc[completed.to_date] << (completed - started) if completed > started
          end
      end

      def percentile_minutes(seconds, percentile)
        return if seconds.blank?

        sorted = seconds.compact.sort
        (sorted[((percentile / 100.0) * (sorted.size - 1)).round] / 60.0).round(1)
      end
    end
  end
end
