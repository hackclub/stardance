# frozen_string_literal: true

class AiImageDetector
  C2PA_MARKERS = %w[
    trainedAlgorithmicMedia
    compositeWithTrainedAlgorithmicMedia
  ].freeze

  def self.ai_generated?(blob)
    bytes = blob.download.force_encoding(Encoding::BINARY)
    C2PA_MARKERS.any? { |marker| bytes.include?(marker) }
  rescue ActiveStorage::FileNotFoundError
    nil
  end
end
