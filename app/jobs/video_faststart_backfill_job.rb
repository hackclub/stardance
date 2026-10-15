class VideoFaststartBackfillJob < ApplicationJob
  queue_as :literally_whenever

  def perform
    blobs = ActiveStorage::Blob.where("content_type LIKE 'video/%'")
    Rails.logger.info "[VideoFaststartBackfill] Enqueuing #{blobs.count} video blobs"

    blobs.find_each do |blob|
      VideoFaststartJob.perform_later(blob)
    end
  end
end
