Rails.application.config.after_initialize do
  next unless defined?(Rails::Server)
  next unless AmbassadorCostStatsService.enabled?

  Rails.logger.info "Syncing ambassador cost stats on startup..."
  SyncAmbassadorCostStatsJob.perform_later
end
