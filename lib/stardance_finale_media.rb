require "open3"

module StardanceFinaleMedia
  # Read metadata once at boot, never on a page request. ffprobe ships in our images.
  def self.load(path)
    return {} unless path.file?

    output, _error, status = Open3.capture3(
      "ffprobe", "-v", "error", "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1", path.to_s
    )
    duration = Float(output.strip, exception: false)
    unless status.success? && duration&.finite? && duration.positive?
      Rails.logger.warn("Finale video has no valid runtime; playback disabled")
      return {}
    end

    { url: "/videos/finale.mp4?v=#{path.mtime.to_i}-#{path.size}", duration: duration }
  rescue SystemCallError => error
    Rails.logger.warn("Finale video unavailable (#{error.class}); playback disabled")
    {}
  end
end
