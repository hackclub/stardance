class WorkshopsController < ApplicationController
  discover_rail_widgets :upcoming_events

  def index
    authorize Workshop
    @live_workshops, @upcoming_workshops = Workshop.upcoming.limit(24).partition { |w| w.starts_at.past? }
    @past_workshops = Workshop.past.limit(12)
  end

  def show
    @workshop = Workshop.find(params[:id])
    authorize @workshop
    @rsvped = @workshop.rsvped?(current_user)
    @rsvp_count = @workshop.rsvps.count
  end
end
