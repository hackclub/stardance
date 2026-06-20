# frozen_string_literal: true

Rails.application.config.to_prepare do
  ActiveSupport.on_load(:active_storage_attachment) do
    after_create_commit do
      AiImageDetectionJob.perform_later(blob) if blob.content_type&.start_with?("image/")
    end
  end
end
