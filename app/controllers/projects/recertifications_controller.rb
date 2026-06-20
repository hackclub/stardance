class Projects::RecertificationsController < ApplicationController
  before_action :set_project

  def create
    authorize @project, :request_recertification?

    @project.with_lock do
      latest_review = @project.ship_reviews.order(created_at: :desc).first

      if latest_review&.pending?
        redirect_to project_path(@project), alert: "A review is already pending for this project." and return
      end

      @project.resubmit_for_review!
      @project.ship_reviews.create!(status: :pending)
      @project.last_ship_event&.update!(certification_status: "pending")
    end

    redirect_to project_path(@project), notice: "Re-certification requested! Your project is back in the review queue."
  rescue AASM::InvalidTransition
    redirect_to project_path(@project), alert: "Your project can't be re-submitted right now."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
