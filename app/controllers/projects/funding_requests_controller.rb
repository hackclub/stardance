class Projects::FundingRequestsController < ApplicationController
  before_action :set_project

  # Submitted from the "Submit Design to Get Project Funding" popup on the
  # project page. Creates a pending funding request for reviewer approval.
  def create
    authorize @project, :ship?

    unless @project.design_stage?
      return redirect_to project_path(@project),
                         alert: "Only projects in the funding stage can request funding."
    end

    if @project.has_pending_funding_request?
      return redirect_to project_path(@project),
                         alert: "You already have a funding request under review."
    end

    @project.certification_funding_requests.create!(
      user: current_user,
      complexity_tier: params[:complexity_tier].to_i,
      requested_amount_cents: params[:requested_amount].to_i * 100,
      status: :pending
    )

    track_event "funding_requested", { project_id: @project.id, complexity_tier: params[:complexity_tier] }
    redirect_to project_path(@project),
                notice: "Funding request submitted! We'll review your design and get back to you."
  rescue ActiveRecord::RecordNotUnique
    redirect_to project_path(@project), alert: "You already have a funding request under review."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: project_path(@project),
                  alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
