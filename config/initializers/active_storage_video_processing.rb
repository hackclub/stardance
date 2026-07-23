# frozen_string_literal: true

Rails.application.config.to_prepare do
  ActiveStorage::Blob.after_create_commit do
    VideoFaststartJob.perform_later(self) if content_type.in?(VideoFaststartJob::FASTSTART_CONTENT_TYPES)
  end
end
