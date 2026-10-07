# frozen_string_literal: true

module DiscoverRail
  class ForgePromoWidget < BaseWidget
    register_as :forge_promo

    URL = "https://forge.hackclub.com/?utm_source=stardance&utm_medium=discover_rail"
    # Ahoy event recorded by PromosController#forge on every click.
    CLICK_EVENT = "forge_promo_clicked"
  end
end
