class HomeController < ApplicationController
  def index
    authorize :home
    @body_class = "app-layout-page"
    @welcoming = params[:welcome] == "1" && current_user.present? && !session[:welcomed]
    @body_class += " home-welcoming" if @welcoming

    session[:welcomed] = true if @welcoming

    @tab = params[:tab].presence || "explore"

    case @tab
    when "faq"
      load_faqs
    when "achievements"
      load_achievements
    when "leaderboard"
      load_leaderboard
    else
      load_feed
      load_composer
      load_recommended_projects

      # when "explore"
      # load_feed
      # load_composer
      # load_recommended_projects
    end
  end

  private

  def load_feed
    devlogs = Post.of_devlogs(join: true)
                  .where(post_devlogs: { deleted_at: nil })
                  .includes(:user, :project, postable: { attachments_attachments: :blob })
                  .order(created_at: :desc)
                  .limit(20)

    ship_events = Post.of_ship_events(join: true)
                      .where.not(post_ship_events: { certification_status: "rejected" })
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
    # def selected_composer_project
    @recommended_projects = Project.excluding_member(current_user)
                                   .where(deleted_at: nil)
                                   .with_banner_priority
                                   .limit(6)
  end

  # Load all FAQs for display in FAQ tab
  def load_faqs
    @faqs = Faq.all
  end

  def load_achievements
    Achievement.all.each { |a| grant_achievement!(a.slug) if a.earned_by?(current_user) }

    user_achievements_by_slug = current_user.achievements.index_by(&:achievement_slug)

    @achievements = Achievement.all.map do |achievement|
      user_achievement = user_achievements_by_slug[achievement.slug.to_s]
      {
        achievement: achievement,
        earned: user_achievement.present?,
        earned_at: user_achievement&.earned_at,
        progress: achievement.progress_for(current_user)
      }
    end

    countable = Achievement.countable_for_user(current_user)
    earned_countable = countable.count { |a| user_achievements_by_slug[a.slug.to_s].present? }
    @achievement_stats = {
      earned: earned_countable,
      total: countable.count
    }
  end

  def load_leaderboard
    scope = User.discoverable
                .joins(:preference)
                .where(user_preferences: { leaderboard_optin: true }, banned: false)

    sorted_users = scope.sort_by { |u| -u.cached_balance }
    @pagy, @users = pagy(:offset, sorted_users, limit: 10)
  end
end
