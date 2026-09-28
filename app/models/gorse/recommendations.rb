# frozen_string_literal: true

class Gorse::Recommendations
  DEFAULT_LIMIT = 6
  CACHE_TTL = 2.minutes
  GUEST_RECOMMENDER = "trending_recent"

  def initialize(user:, client: Gorse::Client.new)
    @user = user
    @client = client
  end

  def posts(limit: DEFAULT_LIMIT, category: "feed")
    if Gorse.enabled?
      recommended_posts(limit, category:)
    else
      []
    end
  end

  def post_candidates(limit: DEFAULT_LIMIT, category: "feed")
    if Gorse.enabled?
      recommended_post_candidates(limit, category:)
    else
      []
    end
  end

  def projects(limit: DEFAULT_LIMIT)
    if user.present? && Gorse.enabled?
      recommended_projects(limit)
    else
      []
    end
  end

  private
    attr_reader :user, :client

    def recommended_posts(limit, category:)
      diversify_posts(recommended_post_candidates(limit, category:), limit:)
    end

    def recommended_post_candidates(limit, category:)
      ids =
        if user.present?
          recommendation_ids(category:, count: limit * 3)
        else
          guest_recommendation_ids(category:, count: limit * 3)
        end
      posts_from_ids(ids, category:)
    end

    def diversify_posts(posts, limit:)
      selected = []
      seen_user_ids = Set.new
      seen_project_ids = Set.new

      posts.each do |post|
        next if post.user_id.present? && seen_user_ids.include?(post.user_id)
        next if post.project_id.present? && seen_project_ids.include?(post.project_id)

        selected << post
        seen_user_ids << post.user_id if post.user_id.present?
        seen_project_ids << post.project_id if post.project_id.present?
        break if selected.size >= limit
      end

      selected
    end

    def posts_from_ids(ids, category: "feed")
      post_ids = ids.filter_map { |id| Gorse::Ids.post_id(id) }
      scope = Gorse::PostPayload.recommendable_feed_scope(user)
      scope = Gorse::PostPayload.hardware_scope(scope) if category == "feed_hardware"
      posts = scope
                                .where(id: post_ids)
                                .includes(:user, :project, :postable)
                                .index_by(&:id)

      post_ids.filter_map { |id| posts[id.to_i] }
    end

    def recommended_projects(limit)
      ids = recommendation_ids(category: "project", count: limit * 3)
      projects = projects_from_ids(ids)
      if projects.size >= limit
        projects.first(limit)
      else
        projects
      end
    end

    def recommendation_ids(category:, count:)
      Rails.cache.fetch(
        [ "gorse", "recommendations", user.id, category, count ],
        expires_in: CACHE_TTL
      ) do
        client.recommend(Gorse::Ids.user(user), category: category, count: count)
      end
    end

    def guest_recommendation_ids(category:, count:)
      Rails.cache.fetch(
        [ "gorse", "recommendations", "guest", GUEST_RECOMMENDER, category, count ],
        expires_in: CACHE_TTL
      ) do
        client.non_personalized(GUEST_RECOMMENDER, category:, count:)
      end
    end

    def projects_from_ids(ids)
      project_ids = ids.filter_map { |id| Gorse::Ids.project_id(id) }
      projects = Gorse::ProjectPayload.recommendable_scope(user)
                                      .where(id: project_ids)
                                      .with_banner_priority
                                      .index_by(&:id)

      project_ids.filter_map { |id| projects[id.to_i] }
    end
end
