# frozen_string_literal: true

module DiscoverRail
  class TerraPortalWidget < BaseWidget
    register_as :terra_portal

    def render?
      helpers.platform_ads_enabled?(user) && Flipper.enabled?(:terra_promo, user)
    end

    URL = "https://terra.hackclub.com/?utm_source=stardance&utm_medium=discover_rail"
  end
end
