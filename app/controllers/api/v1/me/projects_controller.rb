class Api::V1::Me::ProjectsController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    projects = current_api_user.projects.where(deleted_at: nil).order(created_at: :desc)
    @pagy, @projects = pagy(projects, limit: limit)
    render "api/v1/projects/index"
  end
end