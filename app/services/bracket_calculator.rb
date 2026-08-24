class BracketCalculator
  BRACKET_FORMULA = [
    { percent_min: 0.90, percent_max: 1.00, payout_multiplier: 1.00, label: "90-100%" },
    { percent_min: 0.75, percent_max: 0.89, payout_multiplier: 0.85, label: "75-89%" },
    { percent_min: 0.60, percent_max: 0.74, payout_multiplier: 0.70, label: "60-74%" },
    { percent_min: 0.45, percent_max: 0.59, payout_multiplier: 0.55, label: "45-59%" },
    { percent_min: 0.30, percent_max: 0.44, payout_multiplier: 0.40, label: "30-44%" },
    { percent_min: 0.15, percent_max: 0.29, payout_multiplier: 0.25, label: "15-29%" },
    { percent_min: 0.06, percent_max: 0.14, payout_multiplier: 0.10, label: "6-14%" },
    { percent_min: 0.00, percent_max: 0.05, payout_multiplier: 0.025, label: "0-5%" }
  ].freeze

  # Below this share of the leader's total, someone's contribution is too
  # small to bracket meaningfully — pay a flat token amount instead of a
  # multiplier of max_payout.
  MINIMUM_BRACKET_PERCENT = 0.01
  MINIMUM_PARTICIPATION_PAYOUT = 1

  def initialize(leaderboard, max_payout = 1000)
    @leaderboard = leaderboard
    @max_payout = max_payout
  end

  def calculate
    max_count = @leaderboard.map { |u| u[:total] }.max || 1

    results = @leaderboard.map do |user|
      bracket = assign_bracket(user[:total], max_count)
      {
        user: user[:user],
        total: user[:total],
        percent: (user[:total].to_f / max_count * 100).round(1),
        bracket: bracket[:label],
        payout: bracket[:payout]
      }
    end.sort_by { |r| -r[:total] }

    {
      max_count: max_count,
      max_payout: @max_payout,
      results: results,
      total_distributed: results.sum { |r| r[:payout] }
    }
  end

  def calculate_user_payout(user_total, max_count)
    assign_bracket(user_total, max_count)[:payout]
  end

  def brackets
    BRACKET_FORMULA.map do |b|
      b.merge(payout: (@max_payout * b[:payout_multiplier]).round(2))
    end
  end

  private

  def assign_bracket(total, max_count)
    percent = total.to_f / max_count

    if percent < MINIMUM_BRACKET_PERCENT
      return {
        label: "<1%",
        payout: MINIMUM_PARTICIPATION_PAYOUT,
        percent_range: "<1%"
      }
    end

    # BRACKET_FORMULA is sorted highest percent_min first, so the first match
    # is the correct (highest) bracket the percent qualifies for. Matching on
    # percent_min alone (rather than also requiring percent <= percent_max)
    # keeps brackets contiguous — a percent_max-based gap between adjacent
    # tiers (e.g. 0.74 vs 0.75) previously let percentages in that gap fall
    # through to the `.last` fallback and get silently paid the bottom rate.
    bracket = BRACKET_FORMULA.find { |b| percent >= b[:percent_min] }
    raise "no bracket matched percent=#{percent}" unless bracket
    {
      label: bracket[:label],
      payout: (@max_payout * bracket[:payout_multiplier]).round(2),
      percent_range: "#{(bracket[:percent_min] * 100).to_i}-#{(bracket[:percent_max] * 100).to_i}%"
    }
  end
end
