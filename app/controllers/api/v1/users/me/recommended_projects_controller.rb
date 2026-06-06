class Api::V1::Users::Me::RecommendedProjectsController < Api::BaseController
  include ApiAuthenticatable

  def index
    @projects = Gorse::Recommendations.new(user: current_api_user).projects(limit: 6)
    @projects = gorse_fallback if @projects.empty?
    preload_devlog_ids_by_project(@projects)
    render "api/v1/projects/collection"
  end

  private

  def gorse_fallback
    Gorse::ProjectPayload.recommendable_scope(current_api_user)
                         .with_banner_priority
                         .limit(6)
  end
end
