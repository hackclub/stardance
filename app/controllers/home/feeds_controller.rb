class Home::FeedsController < ApplicationController
  include OnboardingResumable

  FEED_LIMIT = 10
  FIRST_PAGE_LIMIT = 3
  RECOMMENDATION_POOL = 100 # after this, we fallback to SQL
  BACKFILL_OVERSAMPLE = 10
  GORSE_TIMEOUT = 0.75
  TABS = %w[for_you following popular newest new_builders].freeze
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
    when "following"     then load_following_feed
    when "popular"       then paginate_and_filter(popular_scope, "popular")
    when "newest"        then paginate_and_filter(newest_scope, "newest")
    when "new_builders"  then paginate_and_filter(new_builders_scope, "new_builders")
    else                      load_for_you_feed
    end

    @liked_devlog_ids = liked_devlog_ids_for(@feed_posts)
    @reposted_post_ids = reposted_post_ids_for(@feed_posts)
    @show_post_views = Flipper.enabled?(:week_2_release, current_user)
  end

  def load_for_you_feed
    return load_seen_mixer_feed if seen_mixer_enabled?

    load_legacy_for_you_feed
  end

  def load_legacy_for_you_feed
    recommended = recommended_posts
    backfill = filtered_feed_scope(Gorse::PostPayload.recommendable_feed_scope(current_user))
      .where.not(id: recommended.map(&:id))

    @pagy = feed_pagy
    @feed_posts, @feed_post_sources, has_next = compose_feed(recommended, backfill, @pagy)
    @pagy.next = @pagy.page + 1 if has_next

    preload_feed_associations(@feed_posts)
  end

  def load_seen_mixer_feed
    @pagy = feed_pagy
    store = Feed::SessionStore.new(user: current_user)
    session = store.read_session(params[:feed_session_id]) if @pagy.page > 1
    session_status = session.present? ? "hit" : "miss"

    if session.present?
      @feed_session_id = params[:feed_session_id]
    else
      @feed_session_id = SecureRandom.uuid
      session = build_mixed_feed_session(store, base_offset: @pagy.offset)
      store.write_session(
        @feed_session_id,
        entries: session[:entries],
        base_offset: session[:base_offset]
      )
    end

    entries = session[:entries] || session["entries"] || []
    base_offset = (session[:base_offset] || session["base_offset"] || 0).to_i
    local_offset = [ @pagy.offset - base_offset, 0 ].max
    page_entries = Array(entries[local_offset, @pagy.limit + 1])
    page_posts = posts_for_session_entries(page_entries)
    posts_by_id = page_posts.index_by(&:id)
    visible_entries = page_entries.filter_map do |entry|
      post_id = (entry[:post_id] || entry["post_id"]).to_i
      post = posts_by_id[post_id]
      [ post, entry[:source] || entry["source"] ] if post.present? && visible_post?(post)
    end

    selected_entries = visible_entries.first(@pagy.limit)
    @feed_posts = selected_entries.map(&:first)
    @feed_post_sources = selected_entries.to_h
    @pagy.next = @pagy.page + 1 if visible_entries.size > @pagy.limit || local_offset + page_entries.size < entries.size

    store.mark_served(@feed_posts.map { |post| Feed::Mixer.canonical_content_id(post) })
    preload_feed_associations(@feed_posts)
    instrument_feed_mix(store:, session_status:)
  end

  def build_mixed_feed_session(store, base_offset:)
    gorse_posts = recommendations.post_candidates(limit: RECOMMENDATION_POOL)
    fresh_posts = filtered_feed_scope(Gorse::PostPayload.recommendable_feed_scope(current_user))
      .limit(RECOMMENDATION_POOL)
      .to_a
    preload(fresh_posts, :postable)

    candidates = (gorse_posts + fresh_posts).uniq(&:id)
    canonical_ids = candidates.filter_map { |post| Feed::Mixer.canonical_content_id(post) }
    candidate_ids = candidates.map(&:id)
    posts_by_id = candidates.index_by(&:id)
    read_post_ids = PostView.where(user: current_user, post_id: candidate_ids + canonical_ids)
                            .where.not(read_at: nil)
                            .pluck(:post_id)
    blocked_content_ids = store.suppressed_ids
    read_post_ids.each do |post_id|
      blocked_content_ids << (Feed::Mixer.canonical_content_id(posts_by_id[post_id]) || post_id)
    end

    result = Feed::Mixer.new(
      gorse_posts:,
      fresh_posts:,
      blocked_content_ids:,
      served_at: store.served_at,
      seed: @feed_session_id,
      max_items: RECOMMENDATION_POOL
    ).call
    @feed_mixer_metrics = result.metrics

    {
      entries: result.entries.map { |entry| { post_id: entry.post.id, source: entry.source } },
      base_offset:
    }
  end

  def posts_for_session_entries(entries)
    ids = entries.map { |entry| (entry[:post_id] || entry["post_id"]).to_i }
    Gorse::PostPayload.recommendable_feed_scope(current_user)
      .where(id: ids)
      .includes(:user, :project, :postable)
      .to_a
  end

  def instrument_feed_mix(store:, session_status:)
    metrics = (@feed_mixer_metrics || {}).merge(
      user_id: current_user.id,
      session_status:,
      cache_healthy: store.cache_healthy,
      page: @pagy.page,
      rendered: @feed_posts.size,
      rendered_ships: @feed_posts.count { |post| post.postable_type == "Post::ShipEvent" }
    )
    ActiveSupport::Notifications.instrument("feed.mixed", metrics)
  end

  def seen_mixer_enabled?
    current_user.present? && Flipper.enabled?(:feed_seen_mixer, current_user)
  end

  def filtered_feed_scope(scope)
    scope
      .joins("LEFT JOIN users feed_authors ON feed_authors.id = posts.user_id")
      .joins("LEFT JOIN projects feed_projects ON feed_projects.id = posts.project_id")
      .where("feed_projects.id IS NULL OR feed_projects.description IS NOT NULL")
      .where("feed_authors.banned = FALSE")
      .order(Arel.sql(quality_latest_order_sql))
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

  def new_builders_scope
    first_devlog_ids = Post.where(postable_type: "Post::Devlog")
      .joins("INNER JOIN post_devlogs ON post_devlogs.id = posts.postable_id")
      .where(post_devlogs: { deleted_at: nil })
      .group(:user_id)
      .select("MIN(posts.id)")

    feed_scope
      .where(postable_type: "Post::Devlog")
      .joins("INNER JOIN post_devlogs ON post_devlogs.id = posts.postable_id")
      .where(id: first_devlog_ids)
      .where(post_devlogs: { deleted_at: nil })
      .where("post_devlogs.duration_seconds > 0")
      .where("posts.created_at >= ?", 7.days.ago)
      .reorder(Arel.sql(<<~SQL.squish))
        (post_devlogs.likes_count + post_devlogs.comments_count) ASC,
        posts.created_at DESC
      SQL
  end

  def visible_post?(post)
    return false unless post.postable.present?
    return true unless post.repost?

    post.visible_repost_original_for?(current_user)
  end

  def recommended_posts
    recommendations.posts(limit: RECOMMENDATION_POOL)
  end

  def feed_pagy
    page = [ params[:page].to_i, 1 ].max
    limit = page == 1 ? FIRST_PAGE_LIMIT : FEED_LIMIT
    offset = page == 1 ? 0 : FIRST_PAGE_LIMIT + (page - 2) * FEED_LIMIT
    FeedPage.new(page: page, limit: limit, offset: offset)
  end

  def compose_feed(recommended, backfill, pagy)
    page_candidate_limit = pagy.limit + 1
    rec_slice = pagy.offset < recommended.size ? Array(recommended[pagy.offset, page_candidate_limit]) : []
    candidates = rec_slice.map { |post| [ post, "recommended" ] }

    remaining = page_candidate_limit - rec_slice.size
    if remaining.positive?
      sql_offset = [ pagy.offset - recommended.size, 0 ].max
      backfill_posts = backfill.offset(sql_offset).limit(remaining * BACKFILL_OVERSAMPLE).to_a
      # Batch-load postables up front: the visibility filter below reads
      # `post.postable` on every candidate, which would otherwise fire one
      # query per post. preload_feed_associations later deep-loads from here.
      preload(backfill_posts, :postable)
      backfill_posts.each do |post|
        next unless post.postable.present?
        next if post.repost? && !post.visible_repost_original_for?(current_user)

        candidates << [ post, "quality_latest" ]
      end
    end

    diverse_posts, sources = select_diverse_candidates(candidates, limit: page_candidate_limit)
    posts = diverse_posts.first(pagy.limit)
    [ posts, sources.slice(*posts), diverse_posts.size > pagy.limit ]
  end

  def select_diverse_candidates(candidates, limit:)
    origins = repost_original_ids(candidates.map(&:first))
    posts = []
    sources = {}
    seen_content_ids = Set.new
    seen_user_ids = Set.new
    seen_project_ids = Set.new

    candidates.each do |post, source|
      content_id = post.repost? ? origins[post.postable_id] : post.id
      next if content_id.nil? || seen_content_ids.include?(content_id)
      next if post.user_id.present? && seen_user_ids.include?(post.user_id)
      next if post.project_id.present? && seen_project_ids.include?(post.project_id)

      seen_content_ids << content_id
      seen_user_ids << post.user_id if post.user_id.present?
      seen_project_ids << post.project_id if post.project_id.present?
      posts << post
      sources[post] = source
      break if posts.size >= limit
    end

    [ posts, sources ]
  end

  def repost_original_ids(posts)
    repost_ids = posts.select(&:repost?).map(&:postable_id)
    return {} if repost_ids.empty?

    Post::Repost.where(id: repost_ids).pluck(:id, :original_post_id).to_h
  end

  def feed_scope
    filtered_feed_scope(Gorse::PostPayload.feed_scope(current_user))
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

  def recommendations
    @recommendations ||= Gorse::Recommendations.new(
      user: current_user,
      client: Gorse::Client.new(timeout_seconds: GORSE_TIMEOUT)
    )
  end
end
