# frozen_string_literal: true

class AiImageDetectionBackfillJob < ApplicationJob
  queue_as :literally_whenever

  BATCH_SIZE = 100

  def perform(cursor = 0)
    blobs = ActiveStorage::Blob.where("content_type LIKE 'image/%'")
                               .where("id > ?", cursor)
                               .order(:id)
                               .limit(BATCH_SIZE)

    blobs.each do |blob|
      next if blob.metadata.key?("ai_generated")

      result = AiImageDetector.ai_generated?(blob)
      next if result.nil?

      blob.update!(metadata: blob.metadata.merge("ai_generated" => result))
    end

    self.class.perform_later(blobs.last.id) if blobs.size == BATCH_SIZE
  end
end
