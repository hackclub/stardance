class Workshops::AttendancesController < ApplicationController
  def create
    @workshop = Workshop.find(params[:workshop_id])
    authorize @workshop, :join?

    unless @workshop.joinable?
      alert = @workshop.ended? ? "This workshop has ended." : "The Zoom link opens #{Workshop::JOIN_WINDOW.inspect} before the workshop starts."
      return redirect_to workshop_path(@workshop), alert: alert
    end

    if @workshop.zoom_link.blank?
      return redirect_to workshop_path(@workshop), alert: "The Zoom link hasn't been posted yet. Hang tight, it'll appear here any minute."
    end

    @workshop.attendances.create_or_find_by!(user: current_user)
    redirect_to @workshop.zoom_link, allow_other_host: true
  end
end
