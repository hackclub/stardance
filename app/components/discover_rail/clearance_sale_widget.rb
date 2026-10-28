# frozen_string_literal: true

module DiscoverRail
  # Rail card selling the live clearance sale: a fan of sale items, the
  # biggest discount, a ticking end time and a way in. Hidden until the
  # clearance_sale flag is on and a sale is live.
  class ClearanceSaleWidget < BaseWidget
    register_as :clearance_sale

    def sale
      @sale ||= helpers.clearance_sale
    end

    def render?
      sale.present?
    end
  end
end
