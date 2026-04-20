class Cache::SitemapJob < ApplicationJob
  queue_as :literally_whenever

  CACHE_KEY = "sitemap_xml"
  CACHE_DURATION = 1.hour

  def self.fetch(force: false)
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_DURATION, force: force) do
      new.send(:build_sitemap)
    end
  end

  def perform(force: false)
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_DURATION, force: force) do
      build_sitemap
    end
  end

  private

  def build_sitemap
    projects = Project.where.not(ship_status: "draft").select(:id, :updated_at)
    users = User.where(banned: false).select(:id, :updated_at)

    ApplicationController.render(
      template: "sitemaps/index",
      formats: [ :xml ],
      assigns: { projects: projects, users: users }
    )
  end
end
