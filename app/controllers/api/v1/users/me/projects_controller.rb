class Api::V1::Users::Me::ProjectsController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    projects = current_api_user.projects.where(deleted_at: nil).order(created_at: :desc)
    @pagy, @projects = pagy(projects, limit: limit)
    render "api/v1/projects/index"
  end

  def create
    @project = Project.new(project_params)

    Project.transaction do
      @project.save!
      @project.memberships.create!(user: current_api_user, role: :owner)
    end

    render "api/v1/projects/show", status: :created
  end

  private

  def project_params
    params.permit(:title, :description, :repo_url, :demo_url, :readme_url, :ai_declaration)
  end
end
