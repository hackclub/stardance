class Api::V1::Posts::CommentsController < Api::BaseController
  include ApiAuthenticatable

  before_action :set_devlog

  def index
    return unless (limit = api_limit)

    comments = @devlog.comments.order(created_at: :asc).includes(:user)
    @pagy, @comments = pagy(comments, limit: limit)
    render json: {
      comments: @comments.map { |c|
        { id: c.id, user_id: c.user_id, body: c.body, created_at: c.created_at }
      },
      pagination: {
        current_page: @pagy.page,
        total_pages: @pagy.pages,
        total_count: @pagy.count,
        next_page: @pagy.next
      }
    }
  end

  def create
    comment = @devlog.comments.build(body: params[:body], user: current_api_user)

    if comment.save
      render json: { id: comment.id, user_id: comment.user_id, body: comment.body, created_at: comment.created_at },
             status: :created
    else
      render json: { errors: comment.errors.full_messages, request_id: request.request_id },
             status: :unprocessable_entity
    end
  end

  def destroy
    comment = @devlog.comments.find(params[:id])

    unless comment.user_id == current_api_user.id
      return render json: { error: "You don't have permission to delete this comment", request_id: request.request_id },
                    status: :forbidden
    end

    comment.soft_delete!
    head :no_content
  end

  private

  def set_devlog
    post = Post.find(params[:post_id])
    unless post.postable_type == "Post::Devlog"
      render json: { error: "This post is not a devlog!", request_id: request.request_id },
             status: :unprocessable_entity
      return
    end
    @devlog = post.postable
  end
end
