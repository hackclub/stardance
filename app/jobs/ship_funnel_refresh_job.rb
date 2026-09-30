class ShipFunnelRefreshJob < ApplicationJob
  queue_as :literally_whenever
  limits_concurrency to: 1, key: "ship_funnel_refresh", duration: 15.minutes

  # A cold public page enqueues this too, so skip unless forced or still cold.
  def perform(force: false)
    return if !force && ShipFunnel.cached

    ShipFunnel.refresh
  end
end
