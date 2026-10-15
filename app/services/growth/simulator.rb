# frozen_string_literal: true

module Growth
  # Duolingo's lever analysis: project DAU forward from today's states using
  # the recent transition rates, then again with one retention rate improved
  # a little each month, and rank the rates by how much DAU they add.
  #
  # Signups either hold at their recent daily average (flat) or scale with
  # yesterday's DAU (word of mouth). With word of mouth, every user a better
  # rate keeps also brings friends, so gains compound, and launching an
  # improvement a week later costs DAU that never comes back.
  class Simulator
    WINDOW = 14
    HORIZON_DAYS = 90
    MONTHLY_LIFT = 0.02
    DELAY_DAYS = 7
    SIGNUPS = %w[word_of_mouth flat].freeze
    LEVERS = %w[nurr curr rurr surr iwaurr reactivation resurrection].freeze
    # Where a state's users go when the window saw nobody leave it.
    DECAY = {
      "new" => "at_risk_wau",
      "current" => "at_risk_wau",
      "reactivated" => "at_risk_wau",
      "resurrected" => "at_risk_wau",
      "at_risk_wau" => "at_risk_mau",
      "at_risk_mau" => "dormant",
      "dormant" => "dormant"
    }.freeze

    # `daily_dau` holds the projected DAU for each day, starting tomorrow.
    Lever = Data.define(:rate, :current_rate, :daily_dau, :lift, :delayed_lift) do
      def dau = daily_dau.last
      def cost_of_waiting = lift - delayed_lift
    end

    attr_reader :new_per_day, :signups_per_dau

    # `snapshots` are one metric's, oldest first.
    def initialize(snapshots, signups: "word_of_mouth")
      recent = snapshots.last(WINDOW)
      @signups = signups
      @start = GrowthDailySnapshot::STATES.to_h { |state| [ state, recent.last.count_for(state).to_f ] }
      @new_per_day = recent.sum(&:new_users).fdiv(recent.size)
      @signups_per_dau = word_of_mouth_rate(snapshots.last(WINDOW + 1))
      @matrix = pooled_matrix(recent)
    end

    def baseline = @baseline ||= project

    def baseline_dau = baseline.last

    def levers
      @levers ||= LEVERS.filter_map do |rate|
        from, to = GrowthDailySnapshot::RATES.fetch(rate)
        current_rate = @matrix[from].fetch(to, 0.0)
        next if current_rate.zero?

        daily_dau = project(lever: [ from, to ])
        delayed = project(lever: [ from, to ], delay: DELAY_DAYS)
        Lever.new(rate:, current_rate:, daily_dau:,
                  lift: daily_dau.last - baseline_dau, delayed_lift: delayed.last - baseline_dau)
      end.sort_by { |lever| -lever.lift }
    end

    private

    # New users per active user the day before, pooled over the window.
    def word_of_mouth_rate(snapshots)
      pairs = snapshots.each_cons(2)
      prior_dau = pairs.sum { |before, _| before.dau }
      prior_dau.zero? ? 0.0 : pairs.sum { |_, after| after.new_users }.fdiv(prior_dau)
    end

    def pooled_matrix(snapshots)
      GrowthDailySnapshot::STATES.index_with do |from|
        targets = Hash.new(0)
        snapshots.each { |snapshot| snapshot.transitions.fetch(from, {}).each { |to, users| targets[to] += users } }
        total = targets.values.sum
        total.zero? ? { DECAY.fetch(from) => 1.0 } : targets.transform_values { |users| users.fdiv(total) }
      end
    end

    # DAU for each day of the horizon. A lever starts improving `delay` days in.
    def project(lever: nil, delay: 0)
      counts = @start
      Array.new(HORIZON_DAYS) do |day|
        improving = day + 1 - delay
        matrix = lever && improving.positive? ? lifted(lever, (1 + MONTHLY_LIFT)**(improving / 30.0)) : @matrix
        counts = step(counts, matrix)
        GrowthDailySnapshot::ACTIVE_STATES.sum { |state| counts[state] }
      end
    end

    def step(counts, matrix)
      following = Hash.new(0.0)
      counts.each do |from, users|
        matrix.fetch(from).each { |to, share| following[to] += users * share }
      end
      following["new"] = signups(counts)
      following
    end

    def signups(counts)
      return @new_per_day if @signups == "flat"

      @signups_per_dau * GrowthDailySnapshot::ACTIVE_STATES.sum { |state| counts[state] }
    end

    # Raises one transition by `factor`, capped at 1, and scales the rest of
    # its row down so the row still sums to 1.
    def lifted((from, to), factor)
      row = @matrix.fetch(from)
      rate = row.fetch(to, 0.0)
      raised = [ rate * factor, 1.0 ].min
      rest = rate < 1 ? (1 - raised) / (1 - rate) : 0.0

      @matrix.merge(from => row.to_h { |target, share| [ target, target == to ? raised : share * rest ] })
    end
  end
end
