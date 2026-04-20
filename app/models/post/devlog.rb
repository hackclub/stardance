# == Schema Information
#
# Table name: post_devlogs
#
#  id                              :bigint           not null, primary key
#  body                            :string
#  comments_count                  :integer          default(0), not null
#  deleted_at                      :datetime
#  duration_seconds                :integer
#  hackatime_projects_key_snapshot :text
#  hackatime_pulled_at             :datetime
#  lapse_video_processing          :boolean          default(FALSE), not null
#  likes_count                     :integer          default(0), not null
#  synced_at                       :datetime
#  tutorial                        :boolean          default(FALSE), not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#
# Indexes
#
#  index_post_devlogs_on_deleted_at  (deleted_at)
#
class Post::Devlog < ApplicationRecord
  include Postable
  include SoftDeletable
  has_paper_trail ignore: [ :likes_count, :comments_count, :lapse_video_processing, :hackatime_pulled_at, :synced_at ]

  BODY_MAX_LENGTH = 4_000

  # flag for tracking if attachments are being uploaded during an update
  attr_accessor :uploading_attachments

  # Version history
  has_many :versions, class_name: "DevlogVersion", foreign_key: :devlog_id, dependent: :destroy

  ACCEPTED_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/webp
    image/heic
    image/heif
    image/gif
    video/mp4
    video/quicktime
    video/webm
    video/x-matroska
  ].freeze

  has_many :likes, as: :likeable, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy

  # only for images – not for videos or gif!
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
            content_type: { in: ACCEPTED_CONTENT_TYPES, spoofing_protection: true },
            size: { less_than: 50.megabytes, message: "is too large (max 50 MB)" },
            processable_file: true
  validate :at_least_one_attachment
  validates :duration_seconds,
            numericality: {
              greater_than_or_equal_to: 15.minutes,
              message: "error, you must log at least 15 minutes to post a devlog"
            },
            allow_nil: true,
            on: :create
  validates :body, presence: true, length: { maximum: BODY_MAX_LENGTH }

  after_create_commit :handle_post_creation
  after_update_commit :update_project_duration_if_changed

  def recalculate_seconds_coded
    return false unless post.project.hackatime_keys.present?
    hackatime_uid = post.user.hackatime_identity&.uid
    previous_devlog = post.project.devlogs.where("post_devlogs.created_at < ?", created_at).order("post_devlogs.created_at desc").first
    start_date = previous_devlog&.created_at || [ post.project.created_at, Date.parse(HackatimeService::START_DATE).beginning_of_day ].min
    end_date = created_at

    HackatimeService.sync_devlog_duration(self, hackatime_uid, start_date.iso8601, end_date.iso8601)
  rescue JSON::ParserError => e
    Rails.logger.error("JSON parse error in recalculate_seconds_coded for Devlog #{id}: #{e.message}")
    false
  rescue => e
    Rails.logger.error("Unexpected error in recalculate_seconds_coded for Devlog #{id}: #{e.message}")
    false
  end

  # Soft delete methods
  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def restore!
    update!(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end

  # Version history methods
  def current_version_number
    versions.maximum(:version_number) || 0
  end

  def create_version!(user:, previous_body:)
    versions.create!(
      user: user,
      reverse_diff: previous_body,
      version_number: current_version_number + 1
    )
  end

  def body_at_version(version_number)
    return body if version_number > current_version_number

    # Start from current and apply reverse diffs backwards
    result = body
    versions.where("version_number > ?", version_number).order(version_number: :desc).each do |version|
      result = version.previous_body
    end
    result
  end

  private

  def at_least_one_attachment
    return if uploading_attachments # allow update as long as they're planning to include an attachment
    return if lapse_video_processing?

    errors.add(:attachments, "must include at least one image or video") unless attachments.attached?
  end

  def handle_post_creation
    PostCreationToSlackJob.perform_later(self)
  end

  def update_project_duration_if_changed
    return unless saved_change_to_duration_seconds?

    post&.project&.recalculate_duration_seconds!
  end
end
