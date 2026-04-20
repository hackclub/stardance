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

end
