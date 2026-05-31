Rails.application.config.after_initialize do
  next unless defined?(Rails::Server) || ENV["WARM_CACHE"] == "true"

  Rails.logger.info "Warming up sitemap cache..."
  Cache::SitemapJob.perform_later
end
