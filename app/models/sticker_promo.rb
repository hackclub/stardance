# frozen_string_literal: true

# Weekly "ship a project by the deadline for a free sticker" promo.
#
# To run the promo again, bump the two constants below (both by ~7 days):
#   DEADLINE       - the machine cutoff; drives the countdown and hides the
#                    promo once it passes. Set in UTC.
#   DEADLINE_LABEL - the human-readable date shown in the popup copy.
#
# The dismissal key is derived from DEADLINE, so changing the date automatically
# re-shows the popup to everyone who dismissed the previous week's promo.
class StickerPromo
  DEADLINE = Time.new(2026, 7, 6, 4, 59, 0, "+00:00").freeze
  DEADLINE_LABEL = "THIS SUNDAY (July 5th, 11:59 PM EST)"

  class << self
    def active? = Time.current < DEADLINE

    # Start of the current promo week; used to check whether a user has shipped
    # a qualifying project in time for the sticker.
    def window_start = DEADLINE - 7.days

    def deadline_iso = DEADLINE.iso8601

    # Week-scoped so each new DEADLINE is treated as a fresh, undismissed promo.
    def dismissal_key = "sticker_promo_#{DEADLINE.strftime('%Y_%m_%d')}"
  end
end
