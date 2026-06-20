class Home::FeedsController < ApplicationController
  include OnboardingResumable

  FEED_LIMIT = 20
  RECOMMENDATION_POOL = 100 # after this, we fallback to SQL
  TABS = %w[for_you following popular newest].freeze
  FeedPage = Struct.new(:page, :limit, :offset, :next, keyword_init: true)

  skip_before_action :remember_page
  before_action :resume_or_expire_onboarding!, if: -> { current_user.present? }

  def show
    authorize :home, :feed?
    @feed_request_id = SecureRandom.uuid
    @current_tab = TABS.include?(params[:tab]) && Flipper.enabled?(:week_3_release, current_user) ? params[:tab] : "for_you"
    load_feed
    load_recommended_projects if first_page? && @current_tab == "for_you"
    render layout: false
  end

  private

  def load_feed
    case @current_tab
    when "following"  then load_following_feed
    when "popular"    then paginate_and_filter(popular_scope, "popular")
    when "newest"     then paginate_and_filter(newest_scope, "newest")
    else                   load_for_you_feed
    end

    @liked_devlog_ids = liked_devlog_ids_for(@feed_posts)
    @reposted_post_ids = reposted_post_ids_for(@feed_posts)
    @show_post_views = Flipper.enabled?(:week_2_release, current_user)
  end

  def load_for_you_feed
    recommended = recommended_posts
    backfill = feed_scope.where.not(id: recommended.map(&:id))

    @pagy = feed_pagy
    @feed_posts, @feed_post_sources, has_next = compose_feed(recommended, backfill, @pagy)
    @pagy.next = @pagy.page + 1 if has_next

    preload_feed_associations(@feed_posts)
  end

  def load_following_feed
    if current_user.blank?
      @pagy = feed_pagy
      @feed_posts = []
      @feed_post_sources = {}
      return
    end

    scope = feed_scope
      .where(
        "posts.user_id IN (:user_ids) OR posts.project_id IN (:project_ids)",
        user_ids: current_user.following.select(:id),
        project_ids: current_user.followed_projects.select(:id)
      )
      .where.not(user_id: current_user.id)
      .reorder(created_at: :desc)

    paginate_and_filter(scope, "following")
  end

  def paginate_and_filter(scope, source_label)
    @pagy = feed_pagy
    page_candidates = scope.offset(@pagy.offset).limit(@pagy.limit + 1).to_a
    preload_feed_associations(page_candidates)
    page_candidates.select! { |p| visible_post?(p) }

    @feed_posts = page_candidates.first(@pagy.limit)
    @feed_post_sources = @feed_posts.index_with { source_label }
    @pagy.next = @pagy.page + 1 if page_candidates.size > @pagy.limit
  end

  def popular_scope
    feed_scope
      .where("posts.created_at >= ?", 7.days.ago)
      .joins("LEFT JOIN post_devlogs ON post_devlogs.id = posts.postable_id AND posts.postable_type = 'Post::Devlog'")
      .reorder(Arel.sql(<<~SQL.squish))
        (
          COALESCE(post_devlogs.likes_count, 0) * 5
          + COALESCE(posts.reposts_count, 0) * 3
          + COALESCE(posts.views_count, 0)
        ) DESC,
        posts.created_at DESC
      SQL
  end

  def newest_scope
    feed_scope.reorder(created_at: :desc)
  end

  def visible_post?(post)
    return false unless post.postable.present?
    return true unless post.repost?

    post.visible_repost_original_for?(current_user)
  end

  def recommended_posts
    Gorse::Recommendations.new(user: current_user).posts(limit: RECOMMENDATION_POOL)
  end

  def feed_pagy
    page = [ params[:page].to_i, 1 ].max
    FeedPage.new(page: page, limit: FEED_LIMIT, offset: (page - 1) * FEED_LIMIT)
  end

  def compose_feed(recommended, backfill, pagy)
    page_candidate_limit = pagy.limit + 1
    rec_slice = pagy.offset < recommended.size ? Array(recommended[pagy.offset, page_candidate_limit]) : []
    candidates = rec_slice.map { |post| [ post, "recommended" ] }

    remaining = page_candidate_limit - rec_slice.size
    if remaining.positive?
      sql_offset = [ pagy.offset - recommended.size, 0 ].max
      backfill.offset(sql_offset).limit(remaining).each do |post|
        next unless post.postable.present?
        next if post.repost? && !post.visible_repost_original_for?(current_user)

        candidates << [ post, "quality_latest" ]
      end
    end

    posts, sources = dedupe_by_content(candidates.first(pagy.limit))
    [ posts, sources, candidates.size > pagy.limit ]
  end

  # don't want to show dupe reposts
  def dedupe_by_content(candidates)
    origins = repost_original_ids(candidates.map(&:first))
    posts = []
    sources = {}
    seen = Set.new

    candidates.each do |post, source|
      key = post.repost? ? origins[post.postable_id] : post.id
      next if key.nil? || seen.include?(key)

      seen << key
      posts << post
      sources[post] = source
    end

    [ posts, sources ]
  end

  def repost_original_ids(posts)
    repost_ids = posts.select(&:repost?).map(&:postable_id)
    return {} if repost_ids.empty?

    Post::Repost.where(id: repost_ids).pluck(:id, :original_post_id).to_h
  end

  def feed_scope
    Gorse::PostPayload.feed_scope(current_user)
      .joins("LEFT JOIN users feed_authors ON feed_authors.id = posts.user_id")
      .joins("LEFT JOIN projects feed_projects ON feed_projects.id = posts.project_id")
      .where("feed_projects.id IS NULL OR feed_projects.description IS NOT NULL")
      .where("feed_authors.banned = FALSE")
      .order(Arel.sql(quality_latest_order_sql))
  end

  def quality_latest_order_sql
    <<~SQL.squish
      (
        CASE WHEN feed_authors.verification_status = 'verified' THEN 40 ELSE 0 END
        + CASE WHEN feed_projects.description IS NOT NULL AND feed_projects.description != '' THEN 10 ELSE 0 END
        + CASE WHEN feed_projects.devlogs_count > 0 THEN 10 ELSE 0 END
        + CASE WHEN feed_projects.shipped_at IS NOT NULL THEN 15 ELSE 0 END
        + COALESCE(posts.reposts_count, 0) * 3
      ) DESC,
      posts.created_at DESC
    SQL
  end

  def preload_feed_associations(posts)
    return if posts.empty?

    preload(posts, [ :user, :project ])

    grouped = posts.group_by(&:postable_type)

    if (devlogs = grouped["Post::Devlog"])
      preload(devlogs, postable: [ :post, { attachments_attachments: :blob } ])
    end

    if (ships = grouped["Post::ShipEvent"])
      preload(ships, postable: [ { attachments_attachments: :blob }, { mission_submission: :mission } ])
    end

    if (reposts = grouped["Post::Repost"])
      preload(reposts, postable: {
        original_post: [ :user, :project, { postable: [ :post, { attachments_attachments: :blob } ] } ]
      })
    end
  end

  def preload(records, associations)
    ActiveRecord::Associations::Preloader.new(records: records, associations: associations).call
  end

  def liked_devlog_ids_for(posts)
    return Set.new unless current_user

    devlog_posts = posts.select { |p| p.postable_type == "Post::Devlog" }
    return Set.new if devlog_posts.empty?

    Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_posts.map(&:postable_id)).pluck(:likeable_id).to_set
  end

  def reposted_post_ids_for(posts)
    return Set.new unless current_user

    repost_target_ids = posts.filter_map do |post|
      if post.postable_type == "Post::Devlog"
        post.id
      elsif post.repost?
        post.postable&.original_post_id
      end
    end
    return Set.new if repost_target_ids.empty?

    Post::Repost
      .where(user: current_user, original_post_id: repost_target_ids)
      .pluck(:original_post_id)
      .to_set
  end

  def load_recommended_projects
    recommendations = Gorse::Recommendations.new(user: current_user)
    projects = recommendations.projects(limit: 6)

    @recommended_projects =
      if projects.any?
        projects
      else
        Gorse::ProjectPayload.recommendable_scope(current_user)
                             .with_banner_priority
                             .limit(6)
      end
  end

  def first_page?
    @pagy.nil? || @pagy.page == 1
  end
end
