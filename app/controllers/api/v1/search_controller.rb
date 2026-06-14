class Api::V1::SearchController < Api::BaseController
  include ApiAuthenticatable

  VALID_TYPES = %w[user project post shop_item].freeze
  VALID_PROJECT_SORT = %w[created_at devlogs_count duration_seconds shipped_at].freeze

  def index
    q = params[:q].to_s.strip
    type = params[:type].to_s

    unless VALID_TYPES.include?(type)
      return render json: { error: "type must be one of: #{VALID_TYPES.join(', ')}", request_id: request.request_id }, status: :bad_request
    end

    if q.blank?
      return render json: { error: "q is required", request_id: request.request_id }, status: :bad_request
    end

    return unless (limit = api_limit)

    send(:"search_#{type}", q, limit)
  end

  private

  def search_user(q, limit)
    users = User.where.not(display_name: [ nil, "" ])
                .where(verification_status: "verified")

    if q.present?
      sq = "%#{ActiveRecord::Base.sanitize_sql_like(q.downcase)}%"
      users = users.where(
        "LOWER(display_name) LIKE :q OR LOWER(first_name) LIKE :q OR LOWER(last_name) LIKE :q",
        q: sq
      )
    end

    @pagy, @users = pagy(users.order(:display_name), limit: limit)
    render "api/v1/search/users"
  end

  def search_project(q, limit)
    projects = Project.where(deleted_at: nil)

    if q.present?
      sq = "%#{ActiveRecord::Base.sanitize_sql_like(q.downcase)}%"
      projects = projects.where("LOWER(title) LIKE :q OR LOWER(description) LIKE :q", q: sq)
    end

    projects = projects.where(ship_status: params[:ship_status]) if params[:ship_status].present?
    projects = projects.where(project_type: params[:project_type]) if params[:project_type].present?
    if params[:category].present?
      projects = projects.where("? = ANY(project_categories)", params[:category])
    end
    if params[:author_id].present?
      projects = projects.joins(:memberships)
                         .where(project_memberships: { user_id: params[:author_id], role: :owner })
    end

    sort_col = VALID_PROJECT_SORT.include?(params[:sort_by]) ? params[:sort_by] : "created_at"
    sort_dir = params[:sort_dir] == "asc" ? :asc : :desc

    @pagy, @projects = pagy(projects.order(sort_col => sort_dir), limit: limit)
    preload_devlog_ids_by_project(@projects)
    render "api/v1/search/projects"
  end

  def search_post(q, limit)
    posts = Post.of_devlogs(join: true)
                .where(post_devlogs: { deleted_at: nil })
                .where(project_id: Project.not_deleted)
                .visible_to(current_api_user)

    if q.present?
      sq = "%#{ActiveRecord::Base.sanitize_sql_like(q.downcase)}%"
      posts = posts.where("LOWER(post_devlogs.body) LIKE ?", sq)
    end

    posts = posts.where(project_id: params[:project_id]) if params[:project_id].present?
    posts = posts.where(user_id: params[:author_id]) if params[:author_id].present?

    posts = posts.includes(postable: { attachments_attachments: :blob })
                 .order(created_at: :desc)

    @pagy, @posts = pagy(posts, limit: limit)
    preload_liked_devlog_ids(@posts.map(&:postable).compact)
    render "api/v1/search/posts"
  end

  def search_shop_item(q, limit)
    items = ShopItem.enabled.listed

    if q.present?
      sq = "%#{ActiveRecord::Base.sanitize_sql_like(q.downcase)}%"
      items = items.where("LOWER(name) LIKE :q OR LOWER(description) LIKE :q", q: sq)
    end

    if params[:category].present?
      items = items.joins(:shop_categories).where(shop_categories: { slug: params[:category] })
    end

    @pagy, @items = pagy(items.order(created_at: :desc), limit: limit)
    @user_region = current_api_user.shop_region || "XX"
    render "api/v1/search/shop_items"
  end
end
