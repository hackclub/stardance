class Api::V1::UserProjectsController < Api::BaseController
  include ApiAuthenticatable

  def index
    user = params[:user_id] == "me" ? current_api_user : User.find(params[:user_id])

    limit = params.fetch(:limit, 100).to_i
    return render json: { error: "Limit must be between 1 and 100" }, status: :bad_request if limit < 1 || limit > 100

    projects = user.projects.where(deleted_at: nil).includes(:devlogs).with_attached_banner

    @pagy, @projects = pagy(projects, page: params[:page], limit: limit)
  end
end
