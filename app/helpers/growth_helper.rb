module GrowthHelper
  # Chart series for the growth-chart Stimulus controller: the row key to
  # plot, its legend label and the brand colour token to draw it in.
  GROWTH_DAU_SERIES = [
    { key: "new", label: "New", color: "--color-brand-mint" },
    { key: "current", label: "Current", color: "--color-brand-blue" },
    { key: "reactivated", label: "Reactivated", color: "--color-brand-lilac" },
    { key: "resurrected", label: "Resurrected", color: "--color-brand-yellow" }
  ].freeze

  GROWTH_AUDIENCE_SERIES = [
    { key: "dau", label: "DAU", color: "--color-brand-mint" },
    { key: "wau", label: "WAU", color: "--color-brand-blue" },
    { key: "mau", label: "MAU", color: "--color-brand-lilac" }
  ].freeze

  GROWTH_RATE_LABELS = {
    "nurr" => "NURR",
    "curr" => "CURR",
    "rurr" => "RURR",
    "surr" => "SURR",
    "iwaurr" => "iWAURR",
    "reactivation" => "Reactivation",
    "resurrection" => "Resurrection"
  }.freeze

  GROWTH_RATE_SERIES = [
    { key: "curr", label: "CURR", color: "--color-brand-blue" },
    { key: "nurr", label: "NURR", color: "--color-brand-mint" },
    { key: "rurr", label: "RURR", color: "--color-brand-lilac" },
    { key: "surr", label: "SURR", color: "--color-brand-yellow" },
    { key: "iwaurr", label: "iWAURR", color: "--color-brand-salmon" }
  ].freeze

  GROWTH_SIGNUP_LABELS = {
    "word_of_mouth" => "Word of mouth",
    "flat" => "Flat"
  }.freeze

  GROWTH_PROJECTION_COLORS = %w[--color-brand-mint --color-brand-lilac --color-brand-yellow].freeze

  # Actual DAU solid, then dashed projections: the baseline and each lever.
  def growth_projection_series(levers)
    [
      { key: "actual", label: "Actual DAU", color: "--color-brand-cream" },
      { key: "baseline", label: "Projected, no change", color: "--color-brand-blue", dashed: true },
      *levers.zip(GROWTH_PROJECTION_COLORS).map do |lever, color|
        { key: lever.rate, label: "#{GROWTH_RATE_LABELS.fetch(lever.rate)} improved", color:, dashed: true }
      end
    ]
  end

  def growth_percent(rate)
    rate ? number_to_percentage(rate * 100, precision: 1) : "—"
  end

  def growth_users(count)
    number_with_delimiter(count.round)
  end
end
