class Certification::YswsAirtableResyncJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    stale_review_ids = Certification::Ysws
      .where("reviewed_at > airtable_synced_at OR (reviewed_at IS NOT NULL AND airtable_synced_at IS NULL)")
      .pluck(:id)

    Rails.logger.info "[YswsAirtableResyncJob] Enqueueing #{stale_review_ids.size} stale review sync(s)"

    stale_review_ids.each do |id|
      Certification::YswsAirtableSyncJob.perform_later(id)
    end
  end
end
