module Admin
  module Raffles
    class WeeksController < Admin::ApplicationController
      before_action :set_week, only: [ :show, :close, :draw, :void_draw ]

      def index
        authorize :admin, :access_raffles?
        @weeks = ::Raffle::Week.chronological.includes(:winner_participant, :draws)
      end

      def show
        authorize :admin, :access_raffles?
        standings = @week.standings
        @standings = @week.leaderboard(limit: standings.size, standings: standings)
        @voided_draws = @week.voided_draws.includes(winner_participant: :user)
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
          return redirect_to admin_raffles_week_path(@week),
                             alert: "This week already has a winner. Void the current draw first to re-draw."
        end

        is_redraw = @week.voided_draws.exists?
        winner = ::Raffle::Weeks::Draw.run(@week)
        if winner
          prefix = is_redraw ? "Re-draw winner" : "Winner drawn"
          redirect_to admin_raffles_week_path(@week),
                      notice: "#{prefix}: #{winner.display_name} (#{winner.code})"
        else
          msg = is_redraw ? "No eligible participants remain after excluding voided winners." :
                            "No eligible participants with entries — cannot draw a winner."
          redirect_to admin_raffles_week_path(@week), alert: msg
        end
      end

      def void_draw
        authorize :admin, :access_raffles?

        unless @week.drawn?
          return redirect_to admin_raffles_week_path(@week), alert: "No draw to void — this week has no winner."
        end

        reason = params[:void_reason].to_s.strip
        if reason.blank?
          return redirect_to admin_raffles_week_path(@week), alert: "A reason is required to void a draw."
        end

        ban = params[:ban_user] == "1"
        voided = ::Raffle::Weeks::VoidDraw.run(@week, reason: reason, ban_user: ban, banned_by: current_user)
        if voided
          name = voided.winner_participant.display_name
          msg = "Draw voided for #{name}."
          msg += " #{name} has been banned." if ban
          msg += " You may now re-draw."
          redirect_to admin_raffles_week_path(@week), notice: msg
        else
          redirect_to admin_raffles_week_path(@week), alert: "Could not void the draw."
        end
      end

      private

      def set_week
        @week = ::Raffle::Week.find(params[:id])
      end
    end
  end
end
