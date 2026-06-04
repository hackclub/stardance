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
            .select("posts.*"),
        Post.of_reposts(join: true)
            .where(post_reposts: { deleted_at: nil })
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

    repost_postables = @posts.select { |p| p.postable_type == "Post::Repost" }.map(&:postable).compact
    if repost_postables.any?
      ActiveRecord::Associations::Preloader.new(
        records: repost_postables,
        associations: { original_post: :postable }
      ).call
    end

    @posts = @posts.reject { |p| p.repost? && !p.visible_repost_original_for?(current_api_user) }

    render "api/v1/posts/index"
  end
end
