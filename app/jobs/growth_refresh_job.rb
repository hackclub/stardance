class GrowthRefreshJob < ApplicationJob
  queue_as :literally_whenever
  limits_concurrency to: 1, key: "growth_refresh", duration: 1.hour

  # Rebuilds activity for the last `days` days, then the snapshots of every
  # finished day among them. Nightly runs use a few days so late Hackatime
  # syncs land; pass a large `days` to backfill.
  def perform(days: 3)
    today = UserActivityDay.today
    Growth::ActivityBuilder.new(from: today - days, to: today).call
    ((today - days)...today).each { |date| Growth::SnapshotBuilder.new(date).call }
  end
end
