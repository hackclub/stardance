class Api::V1::Users::Me::FeedController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    posts = Post.of_devlogs(join: true)
                .where(post_devlogs: { deleted_at: nil })
                .where(project_id: Project.not_deleted)
                .visible_to(current_api_user)
                .order(created_at: :desc)
                .includes(postable: [ :post, { attachments_attachments: :blob } ])

    @pagy, paged = pagy(posts, limit: limit)
    @devlogs = paged.map(&:postable)
    render "api/v1/devlogs/index"
  end
end
