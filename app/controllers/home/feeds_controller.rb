class Home::FeedsController < ApplicationController
  include OnboardingResumable

  FEED_LIMIT = 20

  skip_before_action :remember_page
  before_action :resume_or_expire_onboarding!

  def show
    authorize :home, :feed?
    load_feed
    load_recommended_projects if first_page?
    render layout: false
  end

  private

  def load_feed
    @pagy, posts = pagy(:offset, feed_scope, limit: FEED_LIMIT)

    @feed_posts = posts.select do |post|
      post.postable.present? &&
        (!post.repost? || post.visible_repost_original_for?(current_user))
    end

    preload_feed_associations(@feed_posts)
    @liked_devlog_ids = liked_devlog_ids_for(@feed_posts)
  end

  def feed_scope
    Post.with(
      feed_entries: [
        Post.of_devlogs(join: true)
            .where(post_devlogs: { deleted_at: nil })
            .where(project_id: Project.not_deleted)
            .select("posts.*"),
        Post.of_ship_events(join: true)
            .where.not(post_ship_events: { certification_status: "rejected" })
            .where(project_id: Project.not_deleted)
            .select("posts.*"),
        Post.of_reposts(join: true)
            .where(post_reposts: { deleted_at: nil })
            .select("posts.*")
      ]
    )
    .from("feed_entries AS posts")
    .visible_to(current_user)
    .order(created_at: :desc)
  end

  def preload_feed_associations(posts)
    return if posts.empty?

    preload(posts, [ :user, :project ])

    grouped = posts.group_by(&:postable_type)

    if (devlogs = grouped["Post::Devlog"])
      preload(devlogs, postable: [ :post, :attachments_attachments ])
    end

    if (ships = grouped["Post::ShipEvent"])
      preload(ships, postable: { mission_submission: :mission })
    end

    if (reposts = grouped["Post::Repost"])
      preload(reposts, postable: {
        original_post: [ :user, :project, { postable: [ :post, :attachments_attachments ] } ]
      })
    end
  end

  def preload(records, associations)
    ActiveRecord::Associations::Preloader.new(records: records, associations: associations).call
  end

  def liked_devlog_ids_for(posts)
    devlog_posts = posts.select { |p| p.postable_type == "Post::Devlog" }
    return Set.new if devlog_posts.empty?

    Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_posts.map(&:postable_id)).pluck(:likeable_id).to_set
  end

  def load_recommended_projects
    @recommended_projects = Project.excluding_member(current_user)
                                   .where(deleted_at: nil)
                                   .joins(:banner_attachment)
                                   .includes(banner_attachment: :blob)
                                   .limit(5)
  end

  def first_page?
    @pagy.nil? || @pagy.page == 1
  end
end
