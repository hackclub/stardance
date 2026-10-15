module BukuX3
  class ProgressController < ApplicationController
    skip_before_action :remember_page

    def show
      authorize Event
      response.headers["Cache-Control"] = "no-store"
      event = Event.current
      render json: { percent: event&.percent || Event::STARTING_PERCENT,
                     visual_intensity: event&.visual_intensity || 100,
                     hours: event&.team_hours || { buku: 0, bean: 0 } }
    end
  end
end
