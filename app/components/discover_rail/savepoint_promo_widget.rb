# frozen_string_literal: true

module DiscoverRail
  class SavepointPromoWidget < BaseWidget
    register_as :savepoint_promo

    URL = "https://savepoint.hackclub.com/?utm_source=stardance&utm_medium=discover_rail&utm_campaign=big_type"
    # Ahoy event recorded by PromosController#savepoint on every click.
    CLICK_EVENT = "savepoint_promo_clicked"
    # Save Point ends here, so the card stops showing.
    ENDS_AT = Time.utc(2026, 11, 2, 21)

    # The prizes the rolling word and the sticker step through, in order.
    PRIZES = [
      { word: "keyboard", image: "savepoint/redragon-k617.png" },
      { word: "controller", image: "savepoint/8bitdo-ultimate-2c.png" },
      { word: "mouse", image: "savepoint/logitech-g203.png" },
      { word: "Steam card", image: "savepoint/steam-card.png" }
    ].freeze

    def render?
      Time.current < ENDS_AT && helpers.platform_ads_enabled?(user) && Flipper.enabled?(:"savepoint-promo", user)
    end
  end
end
