module Admin
  module Raffles
    class DashboardController < Admin::ApplicationController
      def show
        authorize :admin, :access_raffles?

        @current_week = ::Raffle::Week.current
        @participant_count = ::Raffle::Participant.count
        @pending_count = ::Raffle::Referral.status_pending.count
        @verified_count = ::Raffle::Referral.status_verified.count
        @leaderboard = leaderboard_for(@current_week)
      end

      private

      def leaderboard_for(week)
        return [] unless week

        week.leaderboard(limit: 20)
      end
    end
  end
end
