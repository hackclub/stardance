class SearchController < ApplicationController
  MAX_RESULTS = 8

  # GET /search/users.json?q=...
  def users
    authorize :search

    q = params[:q].to_s.strip.delete_prefix("@")

    scope = User.discoverable.where.not(display_name: [ nil, "" ])
    scope = scope.where(verification_status: "verified") unless current_user&.admin?
    scope = scope.where("LOWER(display_name) LIKE ?", "#{q.downcase}%") if q.present?

    results = scope
      .order(:display_name)
      .limit(MAX_RESULTS)
      .pluck(:id, :display_name, :slack_id)

    render json: results.map { |id, display_name, slack_id|
      { id: id, display_name: display_name, slack_id: slack_id, avatar: avatar_for(slack_id) }
    }
  end

  # GET /search/projects.json?q=...
  def projects
    authorize :search

    q = params[:q].to_s.strip.delete_prefix("$")

    scope = Project.not_deleted
    scope = scope.where("LOWER(title) LIKE ?", "%#{q.downcase}%") if q.present?

    results = scope
      .order(created_at: :desc)
      .limit(MAX_RESULTS)
      .includes(:memberships)

    render json: results.map { |project|
      { id: project.id, title: project.title, slug: project.id.to_s, user_id: project.memberships.find(&:owner?)&.user_id }
    }
  end

  private

  def avatar_for(slack_id)
    return nil if slack_id.blank?
    "https://cachet.dunkirk.sh/users/#{slack_id}/r"
  end
end
