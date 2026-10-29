# frozen_string_literal: true

module DiscoverRail
  class FallenPromoWidget < BaseWidget
    register_as :fallen_promo

    def render?
      helpers.platform_ads_enabled?(user) && Flipper.enabled?(:"fallen-promo", user)
    end

    URL = "https://fallen.hackclub.com/?utm_source=stardance&utm_medium=discover_rail"
    # Ahoy event recorded by PromosController#fallen on every click.
    CLICK_EVENT = "fallen_promo_clicked"
    DATES = "December 11–14, 2026"
    # Lulu and Sami side by side, left to right, by slot and image.
    CHARACTERS = {
      left: "fallen/lulu.webp",
      right: "fallen/sami.webp"
    }.freeze
  end
end
