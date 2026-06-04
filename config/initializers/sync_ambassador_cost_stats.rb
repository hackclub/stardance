Rails.application.config.after_initialize do
  next unless defined?(Rails::Server) || ENV["SYNC_AMBASSADOR_COST_STATS"] == "true"
  next unless AmbassadorCostStatsService.enabled?

  Rails.logger.info "Syncing ambassador cost stats on startup..."
  SyncAmbassadorCostStatsJob.perform_later
end
