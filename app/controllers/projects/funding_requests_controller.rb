class Projects::FundingRequestsController < ApplicationController
  include ActionItemGate

  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :set_project

  # Submitted from the "Submit Design to Get Project Funding" popup on the
  # project page. Creates a pending funding request for reviewer approval.
  def create
    authorize @project, :ship?

    return if action_items_block_resubmission?(@project.latest_funding_request)

    # Kit missions submit no tier/amount; the model defaults them. Only forward
    # what the form actually sent so a kit request stays valid.
    funding_request = @project.certification_funding_requests.new(user: current_user, status: :pending)
    funding_request.complexity_tier = params[:complexity_tier] if params[:complexity_tier].present?
    funding_request.requested_amount_cents = params[:requested_amount].to_i * 100 if params[:requested_amount].present?
    funding_request.submitter_note = params[:submitter_note] if params[:submitter_note].present?
    funding_request.save!

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
