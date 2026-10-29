class ServerTimeController < ApplicationController
  skip_before_action :remember_page

  def show
    authorize :server_time, :show?
    response.headers["Cache-Control"] = "no-store"
    now = Time.current
    deadline = Rails.application.config.stardance_ends_at
    render json: { now: now.iso8601(3), ends_at: deadline.iso8601(3), ended: now >= deadline }
  end
end
