# frozen_string_literal: true

module DiscoverRail
  class ReferralWidget < BaseWidget
    register_as :referral

    def render?
      participant.present?
    end

    def participant
      return @participant if defined?(@participant)
      @participant = user && (user.raffle_participant || Raffle::Participants::Enroll.run_safely(user))
    end

    def referral_url
      participant.referral_url(:web)
    end

    def verified_count
      referral_counts.fetch("verified", 0)
    end

    def pending_count
      referral_counts.fetch("pending", 0)
    end

    private

    def referral_counts
      @referral_counts ||= participant.referrals.group(:status).count
    end
  end
end
