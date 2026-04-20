class ShipEventPayoutCalculatorJob < ApplicationJob
  queue_as :default

  def perform
    Post::ShipEvent
      .current_voting_scale
      .joins(post: :project)
      .where(certification_status: "approved", payout: nil)
      .find_each do |ship_event|
        next unless ship_event.votes.payout_countable.count >= Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT

        ShipEventPayoutCalculator.apply!(ship_event)
      end
  end
end
