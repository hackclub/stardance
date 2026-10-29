# frozen_string_literal: true

module Growth
  # Everything the admin growth page draws, read from GrowthDailySnapshot.
  class Report
    DAYS = 90
    # Daily rates are noisy at our size, so the rate chart pools a week.
    RATE_WINDOW = 7
    DAU_PARTS = %w[new current reactivated resurrected].freeze
    PROJECTED_LEVERS = 3

    attr_reader :metric, :signups

    def initialize(metric:, signups:)
      @metric = metric
      @signups = signups
      @snapshots = GrowthDailySnapshot.where(snapshot_on: (UserActivityDay.today - DAYS)..)
        .order(:snapshot_on).group_by(&:metric)
    end

    def empty? = selected.empty?

    def latest = selected.last

    def simulator = @simulator ||= Simulator.new(selected, signups:)

    def projected_levers = simulator.levers.first(PROJECTED_LEVERS)

    # Actual DAU, then the baseline and top levers projected on from the last
    # actual day, so each projected line starts where the actual one ends.
    def projection_rows
      history = selected.map { |snapshot| { date: snapshot.snapshot_on, actual: snapshot.dau } }
      history.last.merge!(baseline: latest.dau, **projected_levers.to_h { |lever| [ lever.rate, latest.dau ] })

      future = Simulator::HORIZON_DAYS.times.map do |day|
        { date: latest.snapshot_on + day + 1, baseline: simulator.baseline[day].round(1),
          **projected_levers.to_h { |lever| [ lever.rate, lever.daily_dau[day].round(1) ] } }
      end
      history + future
    end

    # One small DAU chart per metric, split by where today's active users came from.
    def dau_by_metric
      GrowthDailySnapshot::METRICS.keys.to_h do |key|
        [ key, @snapshots.fetch(key, []).map { |snapshot| DAU_PARTS.to_h { |state| [ state, snapshot.count_for(state) ] }.merge(date: snapshot.snapshot_on) } ]
      end
    end

    def audience_rows
      selected.map do |snapshot|
        { date: snapshot.snapshot_on, dau: snapshot.dau, wau: snapshot.wau, mau: snapshot.mau,
          at_risk_wau: snapshot.at_risk_wau, at_risk_mau: snapshot.at_risk_mau }
      end
    end

    def rate_rows
      selected.each_index.map do |index|
        window = selected[[ index - RATE_WINDOW + 1, 0 ].max..index]
        GrowthDailySnapshot::RATES.keys.to_h { |rate| [ rate, pooled_rate(window, rate) ] }
          .merge(date: selected[index].snapshot_on)
      end
    end

    private

    def selected = @snapshots.fetch(metric, [])

    def pooled_rate(window, rate)
      from, to = GrowthDailySnapshot::RATES.fetch(rate)
      leaving = window.sum { |snapshot| snapshot.users_leaving(from).to_i }
      return if leaving.zero?

      window.sum { |snapshot| snapshot.transitions.fetch(from, {}).fetch(to, 0) }.fdiv(leaving)
    end
  end
end
