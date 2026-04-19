class RsvpsController < ApplicationController
  def create
    @rsvp = Rsvp.new(
      email: params[:rsvp][:email].downcase.strip,
      ref: params[:ref].presence || cookies[:referral_code],
      user_agent: request.user_agent,
      ip_address: request.headers["CF-Connecting-IP"] || request.remote_ip
    )

    if @rsvp.save
      redirect_to root_path, notice: "We'll email you when we're ready for liftoff"
    else
      redirect_to root_path, alert: "Please enter a valid email address."
    end
  end
end
