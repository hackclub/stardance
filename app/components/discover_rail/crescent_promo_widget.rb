# frozen_string_literal: true

module DiscoverRail
  class CrescentPromoWidget < BaseWidget
    register_as :crescent_promo

    URL = "https://crescent.hackclub.com/?utm_source=stardance&utm_medium=discover_rail"
    # Ahoy event recorded by PromosController#crescent on every click.
    CLICK_EVENT = "crescent_promo_clicked"
    # The hand dealt into the light, left to right, by slot and face.
    CARDS = {
      left: "crescent-card-ssh.webp",
      middle: "crescent-card-homepage.webp",
      right: "crescent-card-rhythm.webp"
    }.freeze
  end
end
