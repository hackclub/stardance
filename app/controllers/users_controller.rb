class UsersController < ApplicationController
  include TimelinePostPreloading

  discover_rail_widgets :certificate, :achievements, :upcoming_events, :feedback_promo,
                        context: -> { { profile_user: @user } }

  before_action :set_user
  before_action :authorize_user, only: %i[update followers following]

  ALLOWED_TABS = %w[feed devlogs replies projects].freeze
  ACTIVITY_LIMIT = 20

  def show
    if profile_hidden_from_viewer?
      render "users/unverified_placeholder", layout: "application"
      return
    end

    tab = params[:tab].presence_in(ALLOWED_TABS) || "feed"
    load_profile(tab)
  end

  def update
    whodunnit = impersonating? ? real_user&.id : current_user&.id

    PaperTrail.request(whodunnit: whodunnit) do
      if @user.update(user_params)
        respond_to do |format|
          format.turbo_stream do
            flash.now[:notice] = "Profile updated."
            render turbo_stream: turbo_stream.update("flash-region", partial: "shared/flash")
          end
          format.html { redirect_to profile_path(@user.display_name), notice: "Profile updated." }
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
  end

  def followers
    @followers = @user.followers.where(banned: false).order(:display_name)
    render layout: false
  end

  def following
    @following = @user.following.where(banned: false).order(:display_name)
    render layout: false
  end

  private

  def set_user
    @user = User.eager_load(:preference)

    if params[:username].present?
      @user = @user.find_by!("LOWER(display_name) = ?", params[:username].downcase)
    else
      @user = @user.find(params[:id])
    end
  end

  def authorize_user
    authorize @user
  end

  def load_profile(active_tab)
    @active_tab     = active_tab
    @body_class     = "app-layout-page"
    @projects       = profile_projects.load
    @activity       = profile_activity
    @stats          = profile_stats
    @follower_count  = @user.followers.where(banned: false).count
    @following_count = @user.following.where(banned: false).count
    @viewer_follows  = current_user&.follows?(@user) || false
  end

  def profile_projects
    @user.projects
         .includes(:users, banner_attachment: :blob, mission_attachments: { mission: { banner_attachment: :blob } })
         .order(created_at: :desc)
  end

  def profile_activity
    can_view_deleted_devlogs = policy(@user).view_deleted_devlogs?

    scope = Post.left_outer_joins(:project)
                .where("projects.id IS NOT NULL OR posts.postable_type = ?", "Post::Repost")
                .visible_to(current_user)
                .where(user_id: @user.id)
                .preload(:postable)
                .order(created_at: :desc)

    scope = hide_deleted_devlogs(scope) unless can_view_deleted_devlogs
    scope = hide_deleted_reposts(scope)
    scope = hide_rejected_ships(scope)

    build_posts = -> {
      @pagy, posts = pagy(:offset, scope, limit: ACTIVITY_LIMIT)
      preload_timeline_postables(posts)
      posts.select { |post| !post.repost? || post.visible_repost_original_for?(current_user) }
    }

    # Post::Devlog has its own default_scope (SoftDeletable), which the
    # preload above respects regardless of hide_deleted_devlogs — without
    # unscoping, a deleted devlog's postable silently comes back nil and
    # never renders, even when the viewer is authorized to see it.
    can_view_deleted_devlogs ? Post::Devlog.unscoped(&build_posts) : build_posts.call
  end

  def hide_deleted_devlogs(scope)
    deleted_ids = Post::Devlog.unscoped.deleted.pluck(:id)
    scope.where.not(postable_type: "Post::Devlog", postable_id: deleted_ids)
  end

  def hide_deleted_reposts(scope)
    deleted_ids = Post::Repost.unscoped.deleted.pluck(:id)
    scope.where.not(postable_type: "Post::Repost", postable_id: deleted_ids)
  end

  def hide_rejected_ships(scope)
    rejected_ids = Post::ShipEvent.where(certification_status: Post::ShipEvent::HIDDEN_STATUSES).pluck(:id)
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
    return true if @user.banned? && !current_user&.admin?
    return false if @user.identity_verified?
    return false if current_user&.admin?
    return false if current_user&.id == @user.id

    true
  end
end
