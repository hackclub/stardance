class RecalculateProjectDurationsJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    Project.find_each(&:recalculate_duration_seconds!)
  end
end
