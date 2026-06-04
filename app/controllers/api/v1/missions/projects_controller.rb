class Api::V1::Missions::ProjectsController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    mission = Mission.enabled.find_by!(slug: params[:mission_slug])

    attached_ids = mission.attachments.active.where(deleted_at: nil).select(:project_id)
    projects = Project.where(deleted_at: nil, id: attached_ids).order(created_at: :desc)

    @pagy, @projects = pagy(projects, limit: limit)
    render "api/v1/projects/index"
  end
end
