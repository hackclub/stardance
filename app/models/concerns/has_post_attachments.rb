module HasPostAttachments
  extend ActiveSupport::Concern

  included do
    attr_accessor :uploading_attachments

    has_many_attached :attachments do |attachable|
      attachable.variant :large,
                         resize_to_limit: [ 1600, 900 ],
                         format: :webp,
                         preprocessed: true,
                         saver: { strip: true, quality: 75 }

      attachable.variant :medium,
                         resize_to_limit: [ 800, 800 ],
                         format: :webp,
                         preprocessed: false,
                         saver: { strip: true, quality: 75 }

      attachable.variant :thumb,
                         resize_to_limit: [ 400, 400 ],
                         format: :webp,
                         preprocessed: false,
                         saver: { strip: true, quality: 75 }
    end

    validates :attachments,
              content_type: { in: ->(record) { record.class::ACCEPTED_CONTENT_TYPES }, spoofing_protection: true },
              size: { less_than: 50.megabytes, message: "is too large (max 50 MB)" },
              processable_file: true
    validate :at_least_one_attachment, on: :create
    validate :at_most_max_attachments, on: :create
  end

  private

  def at_least_one_attachment
    return if uploading_attachments

    unless attachments.attached?
      label = self.class::ACCEPTED_CONTENT_TYPES.any? { |t| t.start_with?("video/") } ? "image or video" : "image"
      errors.add(:attachments, "must include at least one #{label}")
    end
  end

  def at_most_max_attachments
    if attachments.size > self.class::MAX_ATTACHMENTS
      errors.add(:attachments, "can't exceed #{self.class::MAX_ATTACHMENTS} files")
    end
  end
end
