# frozen_string_literal: true

module DiscoverRail
  class MipmapPromoWidget < BaseWidget
    register_as :mipmap_promo

    def render?
      helpers.platform_ads_enabled?(user)
    end

    URL = "https://mipmap.hackclub.com/?utm_source=stardance&utm_medium=discover_rail"
    # Ahoy event recorded by PromosController#mipmap on every click.
    CLICK_EVENT = "mipmap_promo_clicked"
  end
end
