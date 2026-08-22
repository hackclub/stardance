class Projects::RecertificationsController < ApplicationController
  include ActionItemGate

  before_action :set_project

  def create
    authorize @project, :request_recertification?

    @project.with_lock do
      latest_review = @project.latest_ship_review

      if latest_review&.pending?
        redirect_to project_path(@project), alert: "A review is already pending for this project." and return
      end

      return if action_items_block_resubmission?(latest_review)

      @project.resubmit_for_review!
      ship_event = @project.last_ship_event
      cert = @project.ship_reviews.create!(status: :pending, post_ship_event_id: ship_event&.id)
      ship_event&.update!(certification_status: "pending")

      ::ExternalDashboard::ShipWebhookJob.perform_later(cert.id)
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
