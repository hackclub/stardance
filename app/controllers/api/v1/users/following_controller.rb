class Api::V1::Users::FollowingController < Api::BaseController
  include ApiAuthenticatable

  def index
    return unless (limit = api_limit)

    @user = User.find(params[:user_id])
    users = @user.following.where(banned: false).order(:display_name)
    @pagy, @users = pagy(users, limit: limit)
    @current_api_user = current_api_user
  end
end
