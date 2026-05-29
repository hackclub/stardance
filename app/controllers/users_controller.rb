class UsersController < ApplicationController
  before_action :set_user
  before_action :authorize_user, only: %i[update followers following]

  ALLOWED_TABS = %w[feed devlogs replies projects].freeze

  def show
    if profile_hidden_from_viewer?
      render "users/unverified_placeholder", layout: "application"
      return
    end

    tab = params[:tab].presence_in(ALLOWED_TABS) || "feed"
    load_profile(tab)
  end

  def update
    if @user.update(user_params)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = "Profile updated."
          render turbo_stream: turbo_stream.update("flash-region", partial: "shared/flash")
        end
        format.html { redirect_to @user, notice: "Profile updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = @user.errors.full_messages.to_sentence
          render turbo_stream: turbo_stream.update("flash-region", partial: "shared/flash"), status: :unprocessable_entity
        end
        format.html do
          flash.now[:alert] = @user.errors.full_messages.to_sentence
          load_profile("feed")
          render :show, status: :unprocessable_entity
        end
      end
    end
  end

  def followers
    @followers = @user.followers.order(:display_name)
    render layout: false
  end

  def following
    @following = @user.following.order(:display_name)
    render layout: false
  end

  private

  def set_user
    @user = User.includes(:preference).find(params[:id])
  end

  def authorize_user
    authorize @user
  end

  def load_profile(active_tab)
    @active_tab     = active_tab
    @body_class     = "app-layout-page"
    @projects       = profile_projects
    @activity       = profile_activity
    @stats          = profile_stats
    @follower_count  = @user.followers.count
    @following_count = @user.following.count
    @viewer_follows  = current_user&.follows?(@user) || false
  end

  def profile_projects
    @user.projects
         .select(:id, :title, :description, :created_at, :updated_at,
                 :ship_status, :shipped_at, :devlogs_count, :duration_seconds)
         .includes(:users, banner_attachment: :blob)
         .order(created_at: :desc)
  end

  def profile_activity
    scope = Post.joins(:project)
                .merge(Project.not_deleted)
                .visible_to(current_user)
                .where(user_id: @user.id)
                .preload(:project, :user, postable: [ { attachments_attachments: :blob } ])
                .order(created_at: :desc)

    scope = hide_deleted_devlogs(scope) unless policy(@user).view_deleted_devlogs?
    scope = hide_rejected_ships(scope)
    scope
  end

  def hide_deleted_devlogs(scope)
    deleted_ids = Post::Devlog.unscoped.deleted.pluck(:id)
    scope.where.not(postable_type: "Post::Devlog", postable_id: deleted_ids)
  end

  def hide_rejected_ships(scope)
    rejected_ids = Post::ShipEvent.where(certification_status: "rejected").pluck(:id)
    scope.where.not(postable_type: "Post::ShipEvent", postable_id: rejected_ids)
  end

  def profile_stats
    counts = Post.where(user_id: @user.id).group(:postable_type).count
    {
      devlogs_count:  counts["Post::Devlog"]     || 0,
      ships_count:    counts["Post::ShipEvent"]  || 0,
      votes_count:    @user.votes_count || @user.votes.count,
      projects_count: @projects.size
    }
  end

  def user_params
    params.require(:user).permit(:bio, :banner, :display_name)
  end

  # Non-admin, non-self viewers see a placeholder until the user verifies.
  def profile_hidden_from_viewer?
    return false if @user.identity_verified?
    return false if current_user&.admin?
    return false if current_user&.id == @user.id

    true
  end
end
