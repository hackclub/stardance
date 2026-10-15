# frozen_string_literal: true

ActiveSupport.on_load(:active_storage_blob) do
  after_create_commit do
    VideoFaststartJob.perform_later(self) if content_type.in?(VideoFaststartJob::FASTSTART_CONTENT_TYPES)
  end
end
