class ShipEventPayoutRefreshJob < ApplicationJob
  queue_as :latency_5m

  def perform(ship_event_id = nil)
    Post::ShipEvent.find_by(id: ship_event_id)&.sync_voting_completion! if ship_event_id
    Post::ShipEvent.refresh_payouts!
  end
end
