# frozen_string_literal: true

class AiImageDetectionJob < ApplicationJob
  queue_as :literally_whenever

  def perform(blob)
    result = AiImageDetector.ai_generated?(blob)
    return if result.nil?

    blob.update!(metadata: blob.metadata.merge("ai_generated" => result))
  end
end
