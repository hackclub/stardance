class Api::V1::ProjectsController < Api::V1::PublicApiController
  def index
    scope = api_scope.order(created_at: :desc)
    scope = scope.where("title ILIKE :q OR description ILIKE :q", q: "%#{Project.sanitize_sql_like(params[:query])}%") if params[:query].present?

    @pagy, @projects = pagy(:offset, scope, **pagination_options)
  end

  def show
    @project = api_scope.find(params[:id])
  end

  private
    def api_scope
      Project.preload(:devlog_posts, banner_attachment: :blob)
    end
end
