class Workshops::RsvpsController < ApplicationController
  before_action :set_workshop

  def create
    authorize @workshop, :rsvp?

    if @workshop.ended?
      redirect_to workshop_path(@workshop), alert: "This workshop has already ended."
    else
      @workshop.rsvps.create_or_find_by!(user: current_user)
      notice = if @workshop.joinable?
        "You're on the list! The Zoom link is already open, so jump in whenever."
      else
        "You're on the list! We'll ping you #{Workshop::JOIN_WINDOW.inspect} before it starts."
      end
      redirect_to workshop_path(@workshop), notice: notice
    end
  end

  def destroy
    authorize @workshop, :rsvp?

    @workshop.rsvps.where(user: current_user).destroy_all
    redirect_to workshop_path(@workshop), notice: "Your RSVP has been removed."
  end

  private

    def set_workshop
      @workshop = Workshop.find(params[:workshop_id])
    end
end
