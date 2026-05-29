class HomeController < ApplicationController
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

  def load_feed
    devlogs = Post.of_devlogs(join: true)
                  .visible_to(current_user)
                  .where(post_devlogs: { deleted_at: nil })
                  .where(project_id: Project.not_deleted)
                  .includes(:user, :project)
                  .preload(postable: :attachments_attachments)
                  .order(created_at: :desc)
                  .limit(20)

    ship_events = Post.of_ship_events(join: true)
                      .visible_to(current_user)
                      .where.not(post_ship_events: { certification_status: "rejected" })
                      .where(project_id: Project.not_deleted)
                      .includes(:user, :project, :postable)
                      .order(created_at: :desc)
                      .limit(20)

    all_posts = (devlogs.to_a + ship_events.to_a)
                  .sort_by { |p| -p.created_at.to_i }
                  .first(20)

    @feed_posts = all_posts.select { |post| post.postable.present? }
    @liked_devlog_ids = liked_devlog_ids_for(@feed_posts)
  end

  def liked_devlog_ids_for(posts)
    devlog_posts = posts.select { |p| p.postable_type == "Post::Devlog" }
    return Set.new if devlog_posts.empty?

    Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_posts.map(&:postable_id)).pluck(:likeable_id).to_set
  end

  def load_composer
    @devlog = Post::Devlog.new
    @composer_projects = current_user.projects.order(updated_at: :desc)
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
