# frozen_string_literal: true

module DiscoverRail
  class TorquePromoWidget < BaseWidget
    register_as :torque_promo

    def render?
      helpers.platform_ads_enabled?(user) && Flipper.enabled?(:"torque-promo", user)
    end

    URL = "https://torque.hackclub.com/?utm_source=stardance&utm_medium=discover_rail"
    # Ahoy event recorded by PromosController#torque on every click.
    CLICK_EVENT = "torque_promo_clicked"
  end
end
