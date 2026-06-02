class Api::V1::ProjectsController < Api::BaseController
  include ApiAuthenticatable

  def show
    @project = Project.find_by!(id: params[:id], deleted_at: nil)
  end

  def update
    @project = Project.find_by!(id: params[:id], deleted_at: nil)

    unless @project.memberships.exists?(user: current_api_user)
      return render json: { error: "You dont have permission to update this project!", request_id: request.request_id }, status: :forbidden
    end

    @project.update!(project_params)
    render :show
  end

  private

  def project_params
    params.permit(:title, :description, :repo_url, :demo_url, :readme_url, :ai_declaration)
  end
end
