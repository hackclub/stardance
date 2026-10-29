class Finality::RafflesController < ApplicationController
  def show
    authorize [ :finality, :raffle ]
    @body_class = "app-layout-page"
    @entries = Finality.raffle_counts_for(current_user)
    @opens_at = Finality.window.begin
    @closes_at = Finality.window.end
    @closed = Time.current >= @closes_at
    @upcoming = Time.current < @opens_at

    if current_user
      project = current_user.projects.order(updated_at: :desc).first
      @ship_path = project ? project_path(project) : new_project_path
    end
  end
end
