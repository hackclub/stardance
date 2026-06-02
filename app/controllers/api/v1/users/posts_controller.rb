class Api::V1::Users::PostsController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    user = User.find(params[:user_id])

    posts = Post.with(
      feed_entries: [
        Post.of_devlogs(join: true)
            .where(post_devlogs: { deleted_at: nil })
            .where(user_id: user.id)
            .select("posts.*"),
        Post.of_ship_events(join: true)
            .where.not(post_ship_events: { certification_status: "rejected" })
            .where(user_id: user.id)
            .select("posts.*")
      ]
    )
    .from("feed_entries AS posts")
    .order(created_at: :desc)
    .includes(:postable)

    @pagy, @posts = pagy(posts, limit: limit)

    devlog_postables = @posts.select { |p| p.postable_type == "Post::Devlog" }.map(&:postable).compact
    if devlog_postables.any?
      ActiveRecord::Associations::Preloader.new(
        records: devlog_postables,
        associations: { attachments_attachments: :blob }
      ).call
    end

    render "api/v1/posts/index"
  end
end
