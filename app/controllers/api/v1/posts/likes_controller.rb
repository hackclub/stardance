class Api::V1::Posts::LikesController < Api::BaseController
  include ApiAuthenticatable

  before_action :set_post

  def create
    existing = @devlog.likes.find_by(user: current_api_user)

    if existing
      existing.destroy
      liked = false
    else
      @devlog.likes.create!(user: current_api_user)
      liked = true
    end

    @devlog.reload
    render json: { liked: liked, likes_count: @devlog.likes_count }
  end

  private

  def set_post
    post = Post.find(params[:post_id])

    unless post.postable_type == "Post::Devlog"
      render json: { error: "Only devlog posts can be liked", request_id: request.request_id }, status: :unprocessable_entity
      return
    end

    @devlog = post.postable
  end
end
