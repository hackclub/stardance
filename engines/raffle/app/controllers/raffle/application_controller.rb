module Raffle
  class ApplicationController < ActionController::Base
    include Pagy::Method

    protect_from_forgery with: :exception
    layout "raffle/application"

    helper_method :current_user, :current_participant, :signed_in?, :enrolled?

    skip_forgery_protection only: :not_found

    def not_found
      raise ActionController::RoutingError, "No route matches #{request.path.inspect} on the raffle host"
    end

    private

    def current_user
      return @current_user if defined?(@current_user)
      @current_user = ::User.find_by(id: session[:user_id]) if session[:user_id]
    end

    def current_participant
      return @current_participant if defined?(@current_participant)

      if session[:raffle_participant_id]
        @current_participant = Raffle::Participant.find_by(id: session[:raffle_participant_id])
        return @current_participant if @current_participant
      end

      @current_participant = current_user ? Raffle::Participant.find_by(user_id: current_user.id) : nil
    end

    def signed_in?
      current_user.present? || current_participant&.age_group_adult?
    end

    def enrolled?
      current_participant.present?
    end
  end
end
