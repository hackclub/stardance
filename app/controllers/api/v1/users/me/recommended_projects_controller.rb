class Api::V1::Users::Me::RecommendedProjectsController < Api::BaseController
  include ApiAuthenticatable

  def index
    @projects = Project.excluding_member(current_api_user)
                       .where(deleted_at: nil)
                       .with_banner_priority
                       .limit(6)
    render "api/v1/projects/collection"
  end
end
