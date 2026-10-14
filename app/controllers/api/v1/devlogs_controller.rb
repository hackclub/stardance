class Api::V1::DevlogsController < Api::V1::PublicApiController
  def index
    @pagy, @devlogs = pagy(:offset, api_scope.order(created_at: :desc), **pagination_options)
  end

  def show
    @devlog = api_scope.find(params[:id])
  end

  private
    def api_scope
      Post::Devlog
        .where(id: visible_devlog_posts.select(:postable_id))
        .preload(comments: :user, attachments_attachments: :blob)
    end

    # Devlogs the caller is allowed to see: attached to a live project and
    # authored by a verified user (or by the caller themselves) — the same rule
    # the site's own timelines use. Soft-deleted devlogs are already excluded by
    # Post::Devlog's default scope.
    def visible_devlog_posts
      scope = Post.of_devlogs.visible_to(current_api_user).where(project_id: Project.select(:id))
      scope = scope.where(project_id: project.id) if nested?
      scope
    end

    def nested?
      params[:project_id].present?
    end

    # Resolved rather than filtered on so an unknown or soft-deleted project
    # 404s instead of returning an empty page.
    def project
      @project ||= Project.find(params[:project_id])
    end
end
