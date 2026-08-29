module Certification
  class ClearInsufficientMacAnalysesJob < ApplicationJob
    queue_as :literally_whenever

    STALENESS_THRESHOLD = 3.days

    def perform
      destroyed = Certification::MACAnalysis
        .with_insufficient_data
        .where(created_at: ...STALENESS_THRESHOLD.ago)
        .destroy_all

      Rails.logger.info "[ClearInsufficientMacAnalyses] Destroyed #{destroyed.size} stale insufficient_data analyses" if destroyed.any?
    end
  end
end
