# frozen_string_literal: true

module DiscoverRail
  # Promo card for Receipt (receipt.hackclub.com): write a p5.js sketch, get it
  # printed on a thermal printer and mailed to you. The little 3D printer is
  # drawn by the `receipt-printer` Stimulus controller, which lazy-loads three.js
  # from a CDN only once the card scrolls into view.
  class ReceiptPromoWidget < BaseWidget
    register_as :receipt_promo

    URL = "https://receipt.hackclub.com/?utm_source=stardance&utm_medium=discover_rail"
    ENDS_AT = Time.find_zone!("America/New_York").local(2026, 9, 25)

    def render?
      Time.current < ENDS_AT
    end

    def deadline_iso
      ENDS_AT.iso8601
    end

    # Shown until the countdown controller takes over.
    def ends_label
      "THU 9/24"
    end
  end
end
