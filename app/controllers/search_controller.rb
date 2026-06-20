class SearchController < ApplicationController
  MAX_RESULTS = 8
  GLOBAL_MAX_RESULTS = 6

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

  def global
    authorize :search

    q = params[:q].to_s.squish
    surface = params[:surface].presence_in(%w[command_palette discover_rail]) || "command_palette"
    semantic_results = SemanticSearch.search(
      q,
      viewer: current_user,
      surface: surface,
      limit: GLOBAL_MAX_RESULTS
    )

    results = {
      query: q,
      semantic: SemanticSearch.enabled?,
      commands: command_results(q, surface),
      projects: semantic_results.fetch("project", []),
      posts: semantic_results.fetch("devlog", []) + semantic_results.fetch("ship", []),
      users: merged_user_results(q, semantic_results.fetch("user", []))
    }

    respond_to do |format|
      format.html do
        render partial: "search/#{surface}_results", locals: { results: results }
      end
      format.json { render json: results }
    end
  end

  private

  def command_results(query, surface)
    return [] unless surface == "command_palette"

    Command.search(query, current_user).first(GLOBAL_MAX_RESULTS).map do |command|
      {
        type: "command",
        id: command.id,
        title: command.title,
        subtitle: "Command",
        preview: command.keywords.join(" "),
        path: command.path,
        method: command.post? ? "post" : "get"
      }
    end
  end

  def merged_user_results(query, semantic_users)
    (prefix_user_results(query) + semantic_users)
      .uniq { |result| result[:id] || result["id"] }
      .first(GLOBAL_MAX_RESULTS)
  end

  def prefix_user_results(query)
    q = query.to_s.strip.delete_prefix("@").downcase
    return [] if q.blank?

    scope = User.discoverable.where.not(display_name: [ nil, "" ])
    scope = scope.where(verification_status: "verified") unless current_user&.admin?

    scope
      .where("LOWER(display_name) LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(q)}%")
      .order(:display_name)
      .limit(GLOBAL_MAX_RESULTS)
      .map { |user| SemanticSearch::Document.for(user)&.to_result }
      .compact
  end

  def avatar_for(slack_id)
    return nil if slack_id.blank?
    "https://cachet.hackclub.com/users/#{slack_id}/r"
  end
end
