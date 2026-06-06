module ApiHelper
  def api_followed_project_ids
    @api_followed_project_ids ||= @current_api_user.project_follows.pluck(:project_id).to_set
  end

  def api_followed_user_ids
    @api_followed_user_ids ||= @current_api_user.follows_as_follower.pluck(:followed_id).to_set
  end

  def devlog_ids_for(project)
    @devlog_ids_by_project ? @devlog_ids_by_project.fetch(project.id, []) : project.devlogs.ids
  end
end

