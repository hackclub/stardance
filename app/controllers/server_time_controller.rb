class ServerTimeController < ApplicationController
  skip_before_action :remember_page

  def show
    authorize :server_time, :show?
    response.headers["Cache-Control"] = "no-store"
    now = Time.current
    deadline = Rails.application.config.stardance_finale_at
    duration = Rails.application.config.stardance_finale_video_duration_seconds
    render json: {
      now: now.iso8601(3), ends_at: deadline.iso8601(3), ended: now >= deadline,
      finale: {
        video_url: Rails.application.config.stardance_finale_video_url,
        duration_seconds: duration.finite? && duration.positive? ? duration : 0,
        on_demand: Flipper.enabled?(:finaleondemand, current_user)
      }
    }
  end
end
