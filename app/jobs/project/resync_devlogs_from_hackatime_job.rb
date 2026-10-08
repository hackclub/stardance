class Project::ResyncDevlogsFromHackatimeJob < ApplicationJob
  queue_as :literally_whenever
  retry_on WithAdvisoryLock::FailedToAcquireLock, wait: :polynomially_longer, attempts: 5
  self.enqueue_after_transaction_commit = true

  def perform(project, requested_by_id: nil)
    PaperTrail.request(whodunnit: requested_by_id&.to_s) do
      project.resync_devlogs_from_hackatime_now(audit: requested_by_id.present?)
    end
  rescue StandardError => error
    if requested_by_id
      project.versions.create!(event: "hackatime_resync_failed", whodunnit: requested_by_id.to_s,
        object_changes: { "error" => error.class.name, "attempt" => executions }.to_yaml)
    end
    raise
  end
end
