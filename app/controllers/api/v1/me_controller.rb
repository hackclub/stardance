class Api::V1::MeController < Api::BaseController
  include ApiAuthenticatable

  def show
    @user = current_api_user
    render "api/v1/users/show"
  end

  def update
    current_api_user.update!(me_params)
    @user = current_api_user
    render "api/v1/users/show"
  end

  private

  def me_params
    params.permit(:bio, :display_name, :first_name, :last_name)
  end
end
