module Admin
  class ShipFunnelController < Admin::ApplicationController
    CACHE_KEY = "admin_ship_funnel".freeze
    CACHE_TTL = 1.hour

    def show
      authorize :ship_funnel

      @funnel = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { ShipFunnel.new.to_h.merge(generated_at: Time.current) }
    end

    def refresh
      authorize :ship_funnel

      Rails.cache.delete(CACHE_KEY)
      redirect_to admin_ship_funnel_path, notice: "Jeremy Funnel recomputed."
    end
  end
end
