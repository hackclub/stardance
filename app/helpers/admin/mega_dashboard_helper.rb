module Admin
  module MegaDashboardHelper
    # Durations on this page span minutes to weeks, so a fixed unit reads badly
    # at one end or the other.
    def mega_dash_duration(hours)
      return "—" if hours.blank?
      return "#{(hours * 60).round}m" if hours < 1
      return "#{hours.round(1)}h" if hours < 48

      "#{(hours / 24.0).round(1)}d"
    end

    # Three superlatives, reshuffled on every request. The page has no fixed
    # name on purpose; the admin nav link is the stable one.
    BIG_ADJECTIVES = %w[
      super mega ultra hyper giga colossal titanic supreme monumental immense
      epic massive cosmic stellar galactic astronomical gargantuan almighty
      transcendent legendary infinite prodigious
    ].freeze

    # Net figures read better with an explicit sign: "-4" and "+4" are opposite
    # situations and a bare "4" hides which one it is.
    def mega_dash_signed(value)
      return "—" if value.blank?

      value.positive? ? "+#{value}" : value.to_s
    end

    def mega_dash_title
      "#{BIG_ADJECTIVES.sample(3).map(&:capitalize).join(' ')} Dashboard"
    end
  end
end
