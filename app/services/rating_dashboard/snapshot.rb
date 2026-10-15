module RatingDashboard
  class Snapshot
    Row = Data.define(:ship_event, :votes_count, :pending_flags_count, :status, :blockers) do
      def project = ship_event.project
      def owner = ship_event.payout_recipient
      def voting_started_at = ship_event.voting_started_at
      def voting_completed_at = ship_event.voting_completed_at
      def paid_at = ship_event.paid_at

      def rating_hangtime(now: Time.current)
        return unless voting_started_at

        (voting_completed_at || now) - voting_started_at
      end

      def payment_hangtime
        paid_at - voting_started_at if paid_at && voting_started_at
      end
    end

    PERIODS = { "7" => 7, "30" => 30, "90" => 90, "all" => nil }.freeze
    STATUSES = %w[waiting_for_votes entry_blocked review_open ready_to_pay blocked paid].freeze

    attr_reader :rows, :period

    def initialize(period: "30", now: Time.current)
      @period = PERIODS.key?(period.to_s) ? period.to_s : "30"
      @now = now
      @rows = build_rows
    end

    def counts
      status_counts = rows.group_by(&:status).transform_values(&:size)
      {
        paid: status_counts.fetch("paid", 0),
        unpaid: rows.count { |row| row.status != "paid" },
        waiting_for_votes: status_counts.fetch("waiting_for_votes", 0),
        review_open: status_counts.fetch("review_open", 0),
        ready_to_pay: status_counts.fetch("ready_to_pay", 0),
        blocked: status_counts.fetch("blocked", 0),
        entry_blocked: status_counts.fetch("entry_blocked", 0)
      }
    end

    def blocker_counts
      rows.select { |row| row.status == "blocked" }
          .flat_map(&:blockers)
          .tally
    end

    def oldest_waiting(limit: 10)
      rows.select { |row| row.status == "waiting_for_votes" }
          .sort_by { |row| row.voting_started_at || Time.at(0) }
          .first(limit)
    end

    def metrics
      completed = exact_rows.select { |row| in_period?(row.voting_completed_at) && row.voting_started_at }
      paid = exact_rows.select { |row| in_period?(row.paid_at) && row.payment_hangtime }
      waiting_ages = rows.select { |row| row.status == "waiting_for_votes" && row.voting_started_at }
                         .map { |row| @now - row.voting_started_at }

      {
        rating_median: percentile(completed.map { |row| row.voting_completed_at - row.voting_started_at }, 50),
        rating_p90: percentile(completed.map { |row| row.voting_completed_at - row.voting_started_at }, 90),
        payment_median: percentile(paid.map(&:payment_hangtime), 50),
        payment_p90: percentile(paid.map(&:payment_hangtime), 90),
        current_wait_median: percentile(waiting_ages, 50),
        exact_count: exact_rows.count,
        estimated_count: rows.count { |row| row.ship_event.lifecycle_data_quality == "backfilled_estimated" },
        unknown_count: rows.count { |row| row.ship_event.lifecycle_data_quality.blank? }
      }
    end

    def chart_data
      start_date = period_start.to_date
      (start_date..@now.to_date).map do |date|
        day_end = date.in_time_zone.end_of_day
        completed_today = exact_rows.select { |row| row.voting_completed_at&.to_date == date && row.voting_started_at }
        paid_today = exact_rows.select { |row| row.paid_at&.to_date == date && row.payment_hangtime }

        {
          date: date.strftime("%-m/%-d"),
          queue_size: rows.count { |row| row.voting_started_at && row.voting_started_at <= day_end && (row.voting_completed_at.nil? || row.voting_completed_at > day_end) },
          entered: rows.count { |row| row.voting_started_at&.to_date == date },
          completed: rows.count { |row| row.voting_completed_at&.to_date == date },
          paid: rows.count { |row| row.paid_at&.to_date == date },
          rating_median_hours: seconds_to_hours(percentile(completed_today.map { |row| row.voting_completed_at - row.voting_started_at }, 50)),
          payment_median_hours: seconds_to_hours(percentile(paid_today.map(&:payment_hangtime), 50))
        }
      end
    end

    private

    def build_rows
      ships = Post::ShipEvent.approved
        .voting_payout_path
        .joins(post: :project)
        .where(projects: { hardware_stage: nil })
        .includes(:mission_submission, post: [ :project, { user: :vote_verdict } ])
        .to_a

      ids = ships.map(&:id)
      vote_counts = Vote.payout_countable.where(ship_event_id: ids).group(:ship_event_id).count
      flag_counts = Vote::Event.pending_vote_flags.where(ship_event_id: ids).group(:ship_event_id).count

      ships.map do |ship|
        vote_count = vote_counts.fetch(ship.id, 0)
        flag_count = flag_counts.fetch(ship.id, 0)
        blockers = if ship.payout.nil? && vote_count >= Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT
          blockers_for(ship, flag_count)
        else
          []
        end
        Row.new(
          ship_event: ship,
          votes_count: vote_count,
          pending_flags_count: flag_count,
          status: status_for(ship, vote_count, blockers),
          blockers: blockers
        )
      end
    end

    def status_for(ship, vote_count, blockers)
      return "paid" if ship.payout.present?
      if vote_count < Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT
        return ship.voting_links_present? && ship.hours_at_ship.to_f.positive? ? "waiting_for_votes" : "entry_blocked"
      end
      return "blocked" if blockers.any?
      return "review_open" if ship.payout_basis_locked_at && @now < ship.payout_review_deadline

      "ready_to_pay"
    end

    def blockers_for(ship, flag_count)
      blockers = []
      blockers << "Vote balance deficit" if ship.payout_recipient&.vote_balance.to_i.negative?
      blockers << "Pending vote flags" if flag_count.positive?
      blockers << "No payable hours" unless ship.hours.positive?
      blockers << "Missing recipient" if ship.payout_recipient.blank?
      blockers << "Payout processing disabled" unless Post::ShipEvent.payout_feature_enabled?(ship.payout_recipient)
      blockers
    end

    def exact_rows
      @exact_rows ||= rows.select { |row| row.ship_event.lifecycle_data_quality.in?(%w[live backfilled_exact]) }
    end

    def period_start
      days = PERIODS.fetch(period)
      return rows.filter_map(&:voting_started_at).min || @now.beginning_of_day if days.nil?

      (@now.to_date - (days - 1)).in_time_zone.beginning_of_day
    end

    def in_period?(time)
      time.present? && time >= period_start && time <= @now
    end

    def percentile(values, percentile)
      sorted = values.compact.sort
      return if sorted.empty?

      rank = (percentile / 100.0) * (sorted.length - 1)
      lower = sorted[rank.floor]
      upper = sorted[rank.ceil]
      lower + (upper - lower) * (rank - rank.floor)
    end

    def seconds_to_hours(seconds)
      (seconds / 1.hour.to_f).round(1) if seconds
    end
  end
end
