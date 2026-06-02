class Api::V1::UsersController < Api::BaseController
  include ApiAuthenticatable

  def show
    @user = User.find(params[:id])
    render "api/v1/users/show"
  end
end
