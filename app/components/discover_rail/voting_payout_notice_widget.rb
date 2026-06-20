# frozen_string_literal: true

module DiscoverRail
  class VotingPayoutNoticeWidget < BaseWidget
    register_as :voting_payout_notice

    SHIPS_THRESHOLD = 100

    def current
      @current ||= Post::ShipEvent
        .where(certification_status: "approved", payout: nil)
        .where("votes_count >= ?", Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT)
        .count
        .clamp(0, SHIPS_THRESHOLD)
    end

    def threshold
      SHIPS_THRESHOLD
    end

    def reached?
      current >= SHIPS_THRESHOLD
    end
  end
end
