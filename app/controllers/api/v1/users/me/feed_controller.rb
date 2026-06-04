class Api::V1::Users::Me::FeedController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    posts = Gorse::PostPayload.feed_scope(current_api_user)
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
