class Api::V1::ProjectsController < Api::V1::PublicApiController
  PER_PAGE = 25
  MAX_PER_PAGE = 100

  before_action :set_project, only: [ :show, :update ]

  def index
    scope = Project.where(deleted_at: nil).order(created_at: :desc)
    scope = scope.where("title ILIKE :q OR description ILIKE :q", q: "%#{Project.sanitize_sql_like(params[:query])}%") if params[:query].present?

    limit = params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_PER_PAGE) : PER_PAGE
    @pagy, projects = pagy(:offset, scope, limit: limit)
    render json: { projects: projects.map(&:api_payload) }.merge(pagination_meta)
  end

  def show
    render json: @project.api_payload
  end

  def create
    project = Project.new(project_params)

    Project.transaction do
      project.save!
      project.memberships.create!(user: current_api_user, role: :owner)
    end

    render json: project.api_payload, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    unless ProjectPolicy.new(current_api_user, @project).update?
      return render json: { error: "You do not have permission to update this project" }, status: :forbidden
    end

    if @project.update(project_params)
      render json: @project.api_payload
    else
      render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private
    def set_project
      @project = Project.find_by!(id: params[:id], deleted_at: nil)
    end

    def project_params
      params.permit(:title, :description, :demo_url, :repo_url, :readme_url, :ai_declaration)
    end

    def pagination_meta
      {
        pagination: {
          current_page: @pagy.page,
          total_pages: @pagy.pages,
          total_count: @pagy.count,
          next_page: @pagy.next
        }
      }
    end
end
