module Raffle
  class SessionsController < ApplicationController
    skip_forgery_protection only: :create

    def create
      auth = request.env["omniauth.auth"]
      return redirect_to(root_path, alert: "GitHub sign-in failed.") if auth.blank?

      participant = Raffle::Participant.from_github(auth)
      session[:raffle_participant_id] = participant.id
      redirect_to dashboard_path
    end

    def failure
      redirect_to root_path, alert: "GitHub sign-in failed."
    end

    def destroy
      reset_session
      redirect_to root_path
    end

    def dev_login
      return head(:not_found) unless Rails.env.development? || Rails.env.test?

      handle = params[:handle].presence&.parameterize(separator: "_")&.first(40) || "dev-adult"
      participant = Raffle::Participant.find_or_create_by!(github_uid: "dev-#{handle}") do |p|
        p.github_login = handle
        p.age_group = :adult
      end
      session[:raffle_participant_id] = participant.id
      redirect_to dashboard_path
    end
  end
end
