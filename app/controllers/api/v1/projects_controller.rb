class Api::V1::ProjectsController < Api::V1::PublicApiController
  PER_PAGE = 25
  MAX_PER_PAGE = 100

  def index
    scope = api_scope.order(created_at: :desc)
    scope = scope.where("title ILIKE :q OR description ILIKE :q", q: "%#{Project.sanitize_sql_like(params[:query])}%") if params[:query].present?

    limit = params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_PER_PAGE) : PER_PAGE
    @pagy, projects = pagy(:offset, scope, limit: limit)
    render json: { projects: projects.map(&:api_payload) }.merge(pagination_meta)
  end

  def show
    @project = api_scope.find(params[:id])
    render json: @project.api_payload
  end

  private
    def api_scope
      Project.where(deleted_at: nil).preload(:devlog_posts, banner_attachment: :blob)
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
