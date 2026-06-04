class Api::V1::Projects::FollowsController < Api::BaseController
  include ApiAuthenticatable

  before_action :set_project

  def create
    existing = current_api_user.project_follows.find_by(project: @project)

    if existing
      existing.destroy
      following = false
    else
      follow = current_api_user.project_follows.build(project: @project)
      unless follow.save
        return render json: { errors: follow.errors.full_messages, request_id: request.request_id }, status: :unprocessable_entity
      end
      following = true
    end

    render json: { following: following, followers_count: @project.followers.count }
  end

  private

  def set_project
    @project = Project.find_by!(id: params[:project_id], deleted_at: nil)
  end
end
