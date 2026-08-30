class Project::ResyncDevlogsFromHackatimeJob < ApplicationJob
  queue_as :literally_whenever
  retry_on WithAdvisoryLock::FailedToAcquireLock, wait: :polynomially_longer, attempts: 5

  def perform(project)
    project.resync_devlogs_from_hackatime_now
  end
end
