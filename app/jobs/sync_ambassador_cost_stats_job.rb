# frozen_string_literal: true

class SyncAmbassadorCostStatsJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    unless AmbassadorCostStatsService.enabled?
      Rails.logger.info "[ambassador-cost-stats] skipped: STARDANCE_DATA_ACCESS_KEY not set"
      return
    end

    stat = AmbassadorCostStatsService.sync!
    if stat.nil?
      Rails.logger.warn "[ambassador-cost-stats] skipped: upstream endpoint not enabled"
      return
    end

    Rails.logger.info "[ambassador-cost-stats] synced total_cost_cents=#{stat.total_cost_cents}"
  end
end
