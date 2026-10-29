# frozen_string_literal: true

# Stock-ticker style marquee of recent ships (see ShipTicker). The track is
# rendered twice so the CSS loop can scroll by exactly half its width without a
# visible seam; the copy is hidden from assistive tech.
class ShipTickerComponent < ViewComponent::Base
  def initialize(ticker: ShipTicker.current)
    @ticker = ticker
  end

  def render?
    !@ticker.empty?
  end

  def entries
    @ticker.entries
  end

  def hours(entry)
    "#{helpers.number_with_precision(entry.hours, precision: 1, strip_insignificant_zeros: true)}h"
  end

  # A triangle with rounded corners; downs flip it in CSS.
  def arrow
    tag.svg(tag.path(d: "M5 1 9 9H1Z"), class: "ship-ticker__arrow", viewBox: "0 0 10 10", aria: { hidden: true })
  end

  def stardust(entry)
    safe_join([ helpers.number_with_delimiter(entry.stardust), helpers.stardust_icon(extra_class: "ship-ticker__icon") ], " ")
  end
end
