module Stats
  class ShipFunnelController < ApplicationController
    def show
      authorize :ship_funnel

      @funnel = policy(:ship_funnel).refresh? ? ShipFunnel.fetch : ShipFunnel.cached
      ShipFunnelRefreshJob.perform_later unless @funnel
    end

    def refresh
      authorize :ship_funnel

      ShipFunnel.refresh
      redirect_to stats_ship_funnel_path, notice: "Jeremy Funnel recomputed."
    end
  end
end
