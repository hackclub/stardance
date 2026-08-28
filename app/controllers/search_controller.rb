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
      commands: command_results(q, surface, current_path: params[:current_path]),
      projects: merged_project_results(q, semantic_results.fetch("project", [])),
      posts: semantic_results.fetch("devlog", []) + semantic_results.fetch("ship", []),
      users: merged_user_results(q, semantic_results.fetch("user", [])),
      shop_orders: shop_order_results(q)
    }

    respond_to do |format|
      format.html do
        render partial: "search/#{surface}_results", locals: { results: results }
      end
      format.json { render json: results }
    end
  end

  private

  def command_results(query, surface, current_path: nil)
    return [] unless surface == "command_palette"

    Command.search(query, current_user, current_path: current_path).first(GLOBAL_MAX_RESULTS).map do |command|
      {
        type: "command",
        id: command.id,
        title: command.title,
        subtitle: "Command",
        preview: command.keywords.join(" "),
        path: command.path,
        focus: command.focus,
        method: command.post? ? "post" : "get"
      }
    end
  end

  def merged_project_results(query, semantic_projects)
    (prefix_project_results(query) + semantic_projects)
      .uniq { |r| r[:id] || r["id"] }
      .first(GLOBAL_MAX_RESULTS)
  end

  def prefix_project_results(query)
    q = query.to_s.strip.downcase
    return [] if q.blank?

    Project.not_deleted
      .where("LOWER(title) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(q)}%")
      .order(created_at: :desc)
      .limit(GLOBAL_MAX_RESULTS)
      .map { |p| { id: p.id, title: p.title, subtitle: "Project", path: "/projects/#{p.id}", admin_path: "/admin/projects/#{p.id}" } }
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
      .map { |user| SemanticSearch::Document.for(user)&.to_result&.merge(admin_path: "/admin/users/#{user.id}") }
      .compact
  end

  def shop_order_results(query)
    return [] unless current_user&.admin?

    q = query.to_s.strip
    return [] if q.blank?

    sanitized = ActiveRecord::Base.sanitize_sql_like(q)
    scope = ShopOrder
      .where("tracking_number ILIKE ?", "%#{sanitized}%")
      .or(ShopOrder.where("external_ref ILIKE ?", "%#{sanitized}%"))
    scope = scope.or(ShopOrder.where(id: q)) if q.match?(/\A\d+\z/)

    scope
      .order(created_at: :desc)
      .limit(GLOBAL_MAX_RESULTS)
      .includes(:user, :shop_item)
      .map do |order|
        item_name = order.shop_item&.name || "Unknown item"
        user_name = order.user&.display_name || "Unknown user"
        subtitle = "Order ##{order.id} · #{item_name} · #{user_name} · #{order.aasm_state}"

        { id: order.id, title: order.tracking_number.presence || "Order ##{order.id}", subtitle: subtitle, path: "/admin/shop/orders/#{order.id}" }
      end
  end

  def avatar_for(slack_id)
    return nil if slack_id.blank?
    "https://cachet.dunkirk.sh/users/#{slack_id}/r"
  end
end
