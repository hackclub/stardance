class ExploreController < ApplicationController
  def index
    scope = Post.of_devlogs(join: true)
                .where(post_devlogs: { tutorial: false })
                .where.not(user_id: current_user&.id)
                .joins(:user)
                .includes(:user, :project)
                .preload(:postable)

    scope = scope.where(post_devlogs: { deleted_at: nil }) unless current_user&.can_see_deleted_devlogs?

    if params[:sort] == "following" && current_user
      scope = scope.where(project_id: current_user.project_follows.select(:project_id))
    elsif params[:sort] == "top"
      scope = scope.order(likes_count: :desc)
    else
      scope = scope.order(created_at: :desc)
    end

    @pagy, @devlogs = pagy(scope, limit: 20, client_max_limit: 20)

    respond_to do |format|
      format.html
      format.json do
        html = @devlogs.map do |post|
          render_to_string(
            PostComponent.new(post: post, current_user: current_user, theme: :explore_mixed),
            layout: false,
            formats: [ :html ]
          )
        end.join

        render json: {
          html: html,
          next_page: @pagy.next
        }
      end
    end
  end

  def gallery
    scope = Project.with_banner_priority
                   .where(tutorial: false)
                   .excluding_member(current_user)

    scope = scope.fire if params[:sort] == "well-cooked"

    if params[:sort] == "following" && current_user
      scope = scope.where(id: current_user.project_follows.select(:project_id)).order(created_at: :desc)
    elsif params[:sort] == "top"
      scope = scope.order(devlogs_count: :desc)
    else
      scope = scope.order(created_at: :desc)
    end

    @pagy, @projects = pagy(scope)

    respond_to do |format|
      format.html
      format.json do
        html = @projects.map do |project|
          render_to_string(
            partial: "explore/card",
            locals: { project: project },
            layout: false,
            formats: [ :html ]
          )
        end.join

        render json: {
          html: html,
          next_page: @pagy.next
        }
      end
    end
  end

  def following
    unless current_user
      redirect_to login_path, alert: "You need to sign in to view followed projects." and return
    end

    scope = current_user.followed_projects
                        .where(tutorial: false)
                        .with_attached_banner
                        .order(created_at: :desc)

    @pagy, @projects = pagy(scope)

    respond_to do |format|
      format.html
      format.json do
        html = @projects.map do |project|
          render_to_string(
            partial: "explore/card",
            locals: { project: project },
            layout: false,
            formats: [ :html ]
          )
        end.join

        render json: {
          html: html,
          next_page: @pagy.next
        }
      end
    end
  end

  def extensions
    min_weekly_users = 2
    one_week_ago = 1.week.ago

    project_ids_with_usage = ExtensionUsage
      .where("recorded_at >= ?", one_week_ago)
      .group(:project_id)
      .having("COUNT(DISTINCT user_id) >= ?", min_weekly_users)
      .order(Arel.sql("COUNT(DISTINCT user_id) DESC"))
      .pluck(:project_id)

    @weekly_user_counts = ExtensionUsage
      .where(project_id: project_ids_with_usage)
      .where("recorded_at >= ?", one_week_ago)
      .group(:project_id)
      .count("DISTINCT user_id")

    projects = Project
      .where(id: project_ids_with_usage)
      .with_attached_banner

    if params[:sort] == "following" && current_user
      followed_ids = current_user.project_follows.select(:project_id)
      projects = projects.where(id: followed_ids)
      @projects_with_counts = projects.order(created_at: :desc)
    elsif params[:sort] == "top"
      @projects_with_counts = projects
        .index_by(&:id)
        .values_at(*project_ids_with_usage)
        .compact
    else
      @projects_with_counts = projects.order(created_at: :desc)
    end
  end
end
