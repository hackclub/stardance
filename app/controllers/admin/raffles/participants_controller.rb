module Admin
  module Raffles
    class ParticipantsController < Admin::ApplicationController
      before_action :set_participant, only: [ :show ]

      def index
        authorize :admin, :access_raffles?

        @query = query_param
        @pagy, @participants = pagy(:offset, participants_scope)
        @participants = @participants.to_a
        @referral_counts = if @participants.any?
          ::Raffle::Referral.where(participant_id: @participants.map(&:id))
                            .group(:participant_id)
                            .count
        else
          {}
        end
      end

      def show
        authorize :admin, :access_raffles?

        @referrals = @participant.referrals
                                 .includes(:referred_user, :credited_week)
                                 .order(created_at: :desc)
      end

      private

      def set_participant
        @participant = ::Raffle::Participant.find(params[:id])
      end

      def participants_scope
        participants = ::Raffle::Participant.order(created_at: :desc)
        return participants if @query.blank?

        term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        participants.left_outer_joins(:user)
                    .where("users.display_name ILIKE :term OR raffle_participants.code ILIKE :term OR raffle_participants.github_login ILIKE :term", term: term)
      end

      def query_param
        value = params[:query].presence || params[:search].presence
        return if value.is_a?(Array) || value.is_a?(ActionController::Parameters)

        value.to_s.strip.first(80).presence
      end
    end
  end
end
