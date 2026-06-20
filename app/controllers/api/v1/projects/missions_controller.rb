class Api::V1::Projects::MissionsController < Api::BaseController
  include ApiAuthenticatable

  before_action :set_project

  def create
    mission = Mission.available.find_by!(slug: params[:mission_slug])

    unless mission.prerequisites_met_by?(current_api_user)
      return render json: { error: "Mission prerequisites not met", request_id: request.request_id }, status: :unprocessable_entity
    end

    @project.attach_mission!(mission)
    render json: { mission_slug: mission.slug, attached: true }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message, request_id: request.request_id }, status: :unprocessable_entity
  end

  def destroy
    @project.detach_mission!
    render json: { attached: false }
  rescue StandardError => e
    render json: { error: e.message, request_id: request.request_id }, status: :unprocessable_entity
  end

  private

  def set_project
    @project = current_api_user.projects.find(params[:project_id])
  end
end
