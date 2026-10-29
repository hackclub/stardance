module Admin
  module HourFunnelHelper
    # Funnel totals run from a few hours to hundreds of thousands, so they get
    # a thousands separator and one decimal.
    def hour_funnel_hours(hours)
      "#{number_with_precision(hours.to_f, precision: 1, delimiter: ',')}h"
    end

    def hour_funnel_share(part, whole)
      return "—" unless whole.to_f.positive?

      "#{number_with_precision(part.to_f * 100 / whole.to_f, precision: 1)}%"
    end
  end
end
