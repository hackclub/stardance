class Api::V1::UsersController < Api::BaseController
  include ApiAuthenticatable

  def show
    @user = User.find(params[:id])
    render "api/v1/users/show"
  end

  def find
    @user = User.discoverable.find_by!("LOWER(display_name) = ?", params[:username].to_s.strip.downcase)
    render "api/v1/users/show"
  end
end
