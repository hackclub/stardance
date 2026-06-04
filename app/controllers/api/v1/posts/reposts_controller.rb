class Api::V1::Posts::RepostsController < Api::BaseController
  include ApiAuthenticatable

  before_action :set_post

  def create
    if Post::Repost.find_by(original_post: @post, user: current_api_user)
      return render json: { error: "You have already reposted this post", request_id: request.request_id }, status: :unprocessable_entity
    end

    repost = Post::Repost.new(original_post: @post, user: current_api_user, body: params[:body])

    ActiveRecord::Base.transaction do
      repost.save!
      Post.create!(user: current_api_user, postable: repost)
    end

    @post.reload
    render json: { reposted: true, reposts_count: @post.reposts_count }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages, request_id: request.request_id }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: "You have already reposted this post", request_id: request.request_id }, status: :unprocessable_entity
  end

  def destroy
    repost = Post::Repost.find_by(original_post: @post, user: current_api_user)
    return render json: { error: "Repost not found", request_id: request.request_id }, status: :not_found unless repost

    repost.soft_delete!
    @post.reload
    render json: { reposted: false, reposts_count: @post.reposts_count }
  end

  private

  def set_post
    @post = Post.of_devlogs(join: true)
                .where(post_devlogs: { deleted_at: nil })
                .find(params[:post_id])
  end
end
