module Admin
  module Raffles
    class WeeksController < Admin::ApplicationController
      before_action :set_week, only: [ :show, :close, :draw ]

      def index
        authorize :admin, :access_raffles?
        @weeks = ::Raffle::Week.chronological
      end

      def show
        authorize :admin, :access_raffles?
        standings = @week.standings
        @standings = @week.leaderboard(limit: standings.size, standings: standings)
      end

      def close
        authorize :admin, :access_raffles?

        unless @week.status_active?
          return redirect_to admin_raffles_week_path(@week), alert: "Only the active week can be closed."
        end

        next_week = ::Raffle::Weeks::Close.run(@week)
        notice = next_week ? "Week #{@week.number} archived. Week #{next_week.number} is now open." :
                             "Week #{@week.number} archived. That was the final week — the program is complete."
        redirect_to admin_raffles_weeks_path, notice: notice
      end

      def draw
        authorize :admin, :access_raffles?

        if @week.drawn?
          return redirect_to admin_raffles_week_path(@week), alert: "This week already has a winner."
        end

        winner = ::Raffle::Weeks::Draw.run(@week)
        if winner
          redirect_to admin_raffles_week_path(@week),
                      notice: "Winner drawn: #{winner.display_name} (#{winner.code})"
        else
          redirect_to admin_raffles_week_path(@week),
                      alert: "No eligible participants with entries — cannot draw a winner."
        end
      end

      private

      def set_week
        @week = ::Raffle::Week.find(params[:id])
      end
    end
  end
end
