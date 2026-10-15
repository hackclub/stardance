class VideoFaststartJob < ApplicationJob
  FASTSTART_CONTENT_TYPES = %w[video/mp4 video/quicktime].freeze

  queue_as :literally_whenever

  def perform(blob)
    return unless blob.content_type.in?(FASTSTART_CONTENT_TYPES)
    return unless blob.service.exist?(blob.key)

    blob.open do |input|
      if already_faststarted?(input.path)
        Rails.logger.info "[VideoFaststart] Blob #{blob.id} already faststarted, skipping remux"
      else
        remux_with_faststart!(blob, input.path)
      end
    end

    generate_preview(blob)
  end

  private

    def already_faststarted?(path)
      output, = Open3.capture2e("ffprobe", "-v", "trace", path)
      atoms = output.scan(/type:'(moov|mdat)'/).flatten
      atoms.index("moov").to_i < atoms.index("mdat").to_i
    end

    def remux_with_faststart!(blob, input_path)
      Dir.mktmpdir do |dir|
        output_path = File.join(dir, "faststart.mp4")

        success = system(
          "ffmpeg", "-i", input_path,
          "-c", "copy", "-movflags", "+faststart",
          "-y", output_path,
          out: File::NULL, err: File::NULL
        )

        unless success
          Rails.logger.error "[VideoFaststart] ffmpeg failed for blob #{blob.id}"
          return
        end

        checksum = compute_checksum(output_path)
        blob.service.upload(blob.key, File.open(output_path), checksum: checksum)
        blob.update!(byte_size: File.size(output_path), checksum: checksum)

        Rails.logger.info "[VideoFaststart] Blob #{blob.id} remuxed (#{blob.filename})"
      end
    end

    def compute_checksum(path)
      Digest::MD5.file(path).base64digest
    end

    def generate_preview(blob)
      blob.preview(resize_to_limit: [ 400, 225 ], format: :webp).processed
    rescue => e
      Rails.logger.warn "[VideoFaststart] Preview generation failed for blob #{blob.id}: #{e.message}"
    end
end
