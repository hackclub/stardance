# frozen_string_literal: true

class Gorse::Recommendations
  DEFAULT_LIMIT = 6

  def initialize(user:, client: Gorse::Client.new)
    @user = user
    @client = client
  end

  def posts(limit: DEFAULT_LIMIT)
    if enabled?(:gorse_personalized_feed)
      recommended_posts(limit)
    else
      []
    end
  end

  def projects(limit: DEFAULT_LIMIT)
    if enabled?(:gorse_project_recommendations)
      recommended_projects(limit)
    else
      []
    end
  end

  private
    attr_reader :user, :client

    def enabled?(flag)
      user.present? && Gorse.enabled? && Flipper.enabled?(flag, user)
    end

    def recommended_posts(limit)
      ids = client.recommend(Gorse::Ids.user(user), category: "feed", count: limit * 3)
      posts = posts_from_ids(ids)
      if posts.size >= limit
        posts.first(limit)
      else
        posts
      end
    end

    def posts_from_ids(ids)
      post_ids = ids.filter_map { |id| Gorse::Ids.post_id(id) }
      posts = Gorse::PostPayload.feed_scope(user)
                                .where(id: post_ids)
                                .includes(:user, :project, :postable)
                                .index_by(&:id)

      post_ids.filter_map { |id| posts[id.to_i] }
    end

    def recommended_projects(limit)
      ids = client.recommend(Gorse::Ids.user(user), category: "project", count: limit * 3)
      projects = projects_from_ids(ids)
      if projects.size >= limit
        projects.first(limit)
      else
        projects
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
