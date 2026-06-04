class Api::V1::Users::FollowsController < Api::BaseController
  include ApiAuthenticatable

  before_action :set_target

  def create
    if @target == current_api_user
      return render json: { error: "You cannot follow yourself", request_id: request.request_id }, status: :unprocessable_entity
    end

    existing = current_api_user.follows_as_follower.find_by(followed: @target)

    if existing
      existing.destroy
      following = false
    else
      current_api_user.follows_as_follower.create!(followed: @target)
      following = true
    end

    render json: { following: following, followers_count: @target.followers.count }
  end

  private

  def set_target
    @target = User.find(params[:user_id])
  end
end
