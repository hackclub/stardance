class Home::FeedsController < ApplicationController
  include OnboardingResumable

  FEED_LIMIT = 20
  RECOMMENDATION_POOL = 100 # after this, we fallback to SQL

  skip_before_action :remember_page
  before_action :resume_or_expire_onboarding!, if: -> { current_user.present? }

  def show
    authorize :home, :feed?
    @feed_request_id = SecureRandom.uuid
    load_feed
    load_recommended_projects if first_page?
    render layout: false
  end

  private

  def load_feed
    recommended = recommended_posts
    backfill = feed_scope.where.not(id: recommended.map(&:id))

    total = recommended.size + backfill.count
    @pagy = feed_pagy(total)
    @feed_posts, @feed_post_sources = compose_feed(recommended, backfill, @pagy)

    preload_feed_associations(@feed_posts)
    @liked_devlog_ids = liked_devlog_ids_for(@feed_posts)
  end

  def recommended_posts
    Gorse::Recommendations.new(user: current_user).posts(limit: RECOMMENDATION_POOL)
  end

  def feed_pagy(total)
    last_page = [ (total.to_f / FEED_LIMIT).ceil, 1 ].max
    page = [ [ params[:page].to_i, 1 ].max, last_page ].min
    Pagy::Offset.new(count: total, page: page, limit: FEED_LIMIT)
  end

  def compose_feed(recommended, backfill, pagy)
    rec_slice = pagy.offset < recommended.size ? Array(recommended[pagy.offset, pagy.limit]) : []
    candidates = rec_slice.map { |post| [ post, "recommended" ] }

    remaining = pagy.limit - rec_slice.size
    if remaining.positive?
      sql_offset = [ pagy.offset - recommended.size, 0 ].max
      backfill.offset(sql_offset).limit(remaining).each do |post|
        next unless post.postable.present?
        next if post.repost? && !post.visible_repost_original_for?(current_user)

        candidates << [ post, "quality_latest" ]
      end
    end

    dedupe_by_content(candidates)
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
    return Set.new unless current_user

    devlog_posts = posts.select { |p| p.postable_type == "Post::Devlog" }
    return Set.new if devlog_posts.empty?

    Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_posts.map(&:postable_id)).pluck(:likeable_id).to_set
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
