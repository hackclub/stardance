class Api::V1::ProjectsController < Api::BaseController
  include ApiAuthenticatable

  def index
    limit = params.fetch(:limit, 100).to_i
    return render json: { error: "Limit must be between 1 and 100" }, status: :bad_request if limit < 1 || limit > 100

    projects = Project.where(deleted_at: nil).includes(:devlogs)

    if params[:query].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query])}%"
      projects = projects.where(
        "title ILIKE :q OR description ILIKE :q",
        q: q
      )
    end

    @pagy, @projects = pagy(projects, limit: limit)
  end

  def random
    count = (params[:count] || 1).to_i.clamp(1, 50)

    projects = Project.where(deleted_at: nil).includes(:devlogs)
    projects = projects.where(ship_status: :approved) if ActiveModel::Type::Boolean.new.cast(params[:approved])
    projects = projects.where.not(shipped_at: nil) if ActiveModel::Type::Boolean.new.cast(params[:shipped])
    projects = projects.where.associated(:banner_attachment) if ActiveModel::Type::Boolean.new.cast(params[:has_banner])
    projects = projects.fire if ActiveModel::Type::Boolean.new.cast(params[:fire])

    @projects = projects.order("RANDOM()").limit(count)
  end

  def search
    return render json: { error: "Search is not enabled. Set FERRET=true to activate." }, status: :service_unavailable unless ENV["FERRET"].present?
    return render json: { error: "q parameter is required" }, status: :bad_request if params[:q].blank?

    limit = (params[:limit] || 20).to_i
    return render json: { error: "Limit must be between 1 and 50" }, status: :bad_request if limit < 1 || limit > 50

    @results = Project.ferret_search(params[:q], limit: limit)
    @results = @results.select { |p| p.deleted_at.nil? }
  end

  def show
    @project = Project.find_by!(id: params[:id], deleted_at: nil)
  end

  def ban_status
    unless current_api_user.admin?
      return render json: { error: "Admin API key required" }, status: :forbidden
    end

    @project = Project.unscoped.find(params[:id])
  end

  def create
    @project = Project.new(project_params)

    ActiveRecord::Base.transaction do
      if @project.save
        @project.memberships.create!(user: current_api_user, role: :owner)
        render :show, status: :created
      else
        render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  def update
    @project = Project.find_by!(id: params[:id], deleted_at: nil)

    unless @project.memberships.exists?(user: current_api_user)
      return render json: { error: "You do not have permission to update this project" }, status: :forbidden
    end

    if @project.update(project_params)
      render :show
    else
      render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def project_params
    params.permit(:title, :description, :repo_url, :demo_url, :readme_url, :ai_declaration)
  end
end
