class StreakDailySyncJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    User.joins(:hackatime_identity)
        .joins(:hackatime_projects)
        .where.not(user_hackatime_projects: { project_id: nil })
        .distinct
        .find_each do |user|
      StreakSyncJob.perform_later(user.id)
    end
  end
end
