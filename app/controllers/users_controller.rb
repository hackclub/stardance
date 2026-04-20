class UsersController < ApplicationController
  def stats
    @user = User.find(params[:id])
    authorize :admin, :access_admin_endpoints?

    stats = {
      order_count: @user.shop_orders.real.count,
      total_cookies: @user.ledger_entries.sum(:amount),
      projects_count: @user.projects_count || @user.projects.count,
      created_at: @user.created_at,
      verification_status: @user.verification_status
    }

    render json: stats
  end

  def show
    @user = User.find(params[:id])
    authorize @user

    @projects = @user.projects
                     .select(:id, :title, :created_at, :ship_status, :shipped_at, :devlogs_count)
                     .order(created_at: :desc)
                     .includes(banner_attachment: :blob)

    @activity = Post.joins(:project)
                          .merge(Project.not_deleted)
                          .where(user_id: @user.id)
                          .order(created_at: :desc)
                          .preload(:project, :user, postable: [ { attachments_attachments: :blob } ])

    unless current_user&.admin?
      approved_ship_event_ids = Post::ShipEvent.where(certification_status: "approved").pluck(:id)
      @activity = @activity.where("postable_type != 'Post::ShipEvent' OR postable_id IN (?)", approved_ship_event_ids.presence || [ 0 ])
    end

    # Filter out deleted devlogs for users who can't see them
    unless current_user&.can_see_deleted_devlogs?
      deleted_devlog_ids = Post::Devlog.unscoped.deleted.pluck(:id)
      @activity = @activity.where.not(postable_type: "Post::Devlog", postable_id: deleted_devlog_ids)
    end

    post_counts_by_type = Post.where(user_id: @user.id).group(:postable_type).count
    posts_count = post_counts_by_type.values.sum
    ships_count = post_counts_by_type["Post::ShipEvent"] || 0

    votes_count = @user.votes_count || Vote.where(user_id: @user.id).count

    @stats = {
      posts_count: posts_count,
      projects_count: @user.projects_count || @user.projects.size,
      ships_count: ships_count,
      votes_count: votes_count,
      hours_today: (@user.devlog_seconds_today / 3600.0).round(1),
      hours_all_time: (@user.devlog_seconds_total / 3600.0).round(1)
    }

    achievements_by_slug = Achievement.all.index_by { |a| a.slug.to_s }
    earned_slugs = @user.achievements.order(earned_at: :desc).pluck(:achievement_slug)
    @earned_achievements = earned_slugs.filter_map { |slug| achievements_by_slug[slug] }

    @fulfilled_orders = @user.shop_orders
                             .real
                             .where(aasm_state: "fulfilled")
                             .includes(:shop_item)
                             .order(created_at: :desc)
  end
end
