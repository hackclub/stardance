Rails.application.config.after_initialize do
  next unless defined?(Rails::Server) || ENV["WARM_CACHE"] == "true"

  Rails.logger.info "Clearing landing page RSVP and signup counts cache on application boot..."
  Rails.cache.delete("landing/rsvp_count")
  Rails.cache.delete("landing/signup_count")
  Rails.logger.info "Landing page RSVP and signup counts cache cleared."

  Rails.logger.info "Warming up sitemap cache..."
  Cache::SitemapJob.perform_later
end
