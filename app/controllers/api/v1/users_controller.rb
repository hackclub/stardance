class Api::V1::UsersController < Api::V1::AdminApiController
  def lookup
    return render json: { error: "slack_id is required" }, status: :bad_request if params[:slack_id].blank?

    user = User.find_by!(slack_id: params[:slack_id])
    render json: { id: user.id, slack_id: user.slack_id, display_name: user.display_name }
  end
end
