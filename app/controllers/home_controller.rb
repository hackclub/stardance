class HomeController < ApplicationController
  include OnboardingResumable

  before_action :resume_or_expire_onboarding!, only: :index

  def index
    authorize :home
    @body_class = "app-layout-page"
    @welcoming = params[:welcome] == "1" && current_user.present? && !session[:welcomed]
    @body_class += " home-welcoming" if @welcoming

    session[:welcomed] = true if @welcoming

    load_feed
    load_composer
    load_recommended_projects
  end

  private

  # A guest who bailed mid-wizard and lands on /home: bring them back to where
  # they left off if they started within the window, otherwise treat the
  # placeholder account as expired and drop them on the landing page.
  def resume_or_expire_onboarding!
    user = current_user
    return unless onboarding_in_progress?(user)

    if onboarding_fresh?(user)
      redirect_to onboarding_resume_path(user)
    else
      reset_session
      redirect_to root_path
    end
  end

  def load_feed
    devlogs = Post.of_devlogs(join: true)
                  .visible_to(current_user)
                  .where(post_devlogs: { deleted_at: nil })
                  .where(project_id: Project.not_deleted)
                  .includes(:user, :project)
                  .preload(postable: { attachments_attachments: :blob })
                  .order(created_at: :desc)
                  .limit(20)

    ship_events = Post.of_ship_events(join: true)
                      .visible_to(current_user)
                      .where.not(post_ship_events: { certification_status: "rejected" })
                      .where(project_id: Project.not_deleted)
                      .includes(:user, :project)
                      .preload(postable: { mission_submission: :mission })
                      .order(created_at: :desc)
                      .limit(20)

    reposts = Post.of_reposts(join: true)
                  .visible_to(current_user)
                  .includes(:user, postable: { original_post: [ :user, :project, :postable ] })
                  .order(created_at: :desc)
                  .limit(20)
                  .select { |post| post.visible_repost_original_for?(current_user) }

    all_posts = (devlogs.to_a + ship_events.to_a + reposts)
                  .sort_by { |p| -p.created_at.to_i }
                  .first(20)

    @feed_posts = all_posts.select { |post| post.postable.present? }
    @liked_devlog_ids = liked_devlog_ids_for(@feed_posts)
    @reposted_post_ids = reposted_post_ids_for(@feed_posts)
  end

  def liked_devlog_ids_for(posts)
    devlog_posts = posts.select { |p| p.postable_type == "Post::Devlog" }
    return Set.new if devlog_posts.empty?

    Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_posts.map(&:postable_id)).pluck(:likeable_id).to_set
  end

  def reposted_post_ids_for(posts)
    target_ids = posts.filter_map do |p|
      case p.postable_type
      when "Post::Devlog" then p.id
      when "Post::Repost" then p.postable&.original_post_id
      end
    end
    return Set.new if target_ids.empty?

    Post::Repost.where(user: current_user, original_post_id: target_ids).pluck(:original_post_id).to_set
  end

  def load_composer
    @devlog = Post::Devlog.new
    @composer_projects = current_user.projects.includes(:hackatime_projects).order(updated_at: :desc)
    @selected_project = selected_composer_project
  end

  def selected_composer_project
    if params[:project_id].present?
      @composer_projects.find_by(id: params[:project_id]) || @composer_projects.first
    else
      @composer_projects.first
    end
  end

  def load_recommended_projects
    @recommended_projects = Project.excluding_member(current_user)
                                   .where(deleted_at: nil)
                                   .with_banner_priority
                                   .limit(6)
  end
end
