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
#  likes_count                     :integer          default(0), not null
#  phase                           :string
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
  include Mentionable
  include SemanticSearchIndexable
  has_paper_trail ignore: [ :likes_count, :comments_count, :hackatime_pulled_at, :synced_at ]
  semantic_search_indexable type: "devlog"

  # Ignore devlog_review_id column before removing it in migration
  self.ignored_columns += [ "devlog_review_id" ]

  # Which hardware stage this devlog was logged in. Stamped from the project's
  # hardware_stage at creation (nil for software). Only build-phase time feeds
  # the ship payout basis — see Post::ShipEvent#hours.
  PHASES = %w[design build].freeze

  scope :design_phase, -> { where(phase: "design") }
  scope :build_phase, -> { where(phase: "build") }

  BODY_MAX_LENGTH = 4_000
  MAX_ATTACHMENTS = 4
  ATTACHMENT_MAX_SIZE = 50.megabytes
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

  include HasPostAttachments

  # Version history
  has_many :versions, class_name: "DevlogVersion", foreign_key: :devlog_id, dependent: :destroy

  # Review association
  has_one :devlog_review, class_name: "Certification::Devlog", foreign_key: :post_devlog_id, dependent: :destroy

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
            size: { less_than: ATTACHMENT_MAX_SIZE, message: "is too large (max 50 MB)" },
            processable_file: true
  validate :at_least_one_attachment
  validate :at_most_max_attachments
  validates :duration_seconds,
            numericality: {
              greater_than_or_equal_to: 15.minutes,
              message: "error, you must log at least 15 minutes to post a devlog"
            },
            allow_nil: true,
            on: :create
  # Call normalizer prior to validation
  before_validation :normalize_line_endings
  validates :body, presence: true, length: { maximum: BODY_MAX_LENGTH }

  private

  # Normalize line endings (\r\n for now) to \n
  def normalize_line_endings
    self.body = body.gsub("\r\n", "\n") if body.present?
  end

  after_create_commit :handle_post_creation
  after_update_commit :update_project_duration_if_changed
  after_update_commit :update_devlogs_count_on_soft_delete

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

  # Best-effort per-Hackatime-project time split for this devlog's logged
  # window — admin-only debug info (see Posts::CardComponent). There's no
  # persisted per-project breakdown (duration_seconds is one aggregate total),
  # so this reconstructs it live: one Hackatime API call per project key that
  # was linked at devlog-creation time, scoped to the same window duration_seconds
  # was originally computed from. Cached indefinitely once computed, since a
  # past devlog's time window never changes.
  def hackatime_project_breakdown
    keys = hackatime_projects_key_snapshot.to_s.split(",").map(&:strip).reject(&:blank?)
    return [] if keys.empty? || hackatime_projects_key_snapshot == "test"

    author = post&.user
    hackatime_uid = author&.hackatime_identity&.uid
    return [] if hackatime_uid.blank?

    project = post.project
    return [] unless project

    Rails.cache.fetch([ "devlog_hackatime_breakdown", id ], expires_in: 30.days) do
      access_token = author.hackatime_identity&.access_token
      window_start = project.devlog_window_start(created_at)

      breakdown = keys.map do |key|
        seconds = HackatimeService.fetch_total_seconds_for_projects(
          hackatime_uid, [ key ], start_date: window_start.iso8601, end_date: created_at.iso8601, access_token: access_token
        ).to_i
        { name: key, seconds: seconds }
      end

      total = breakdown.sum { |b| b[:seconds] }
      breakdown.each { |b| b[:percent] = total.positive? ? (b[:seconds] * 100.0 / total).round(1) : 0.0 }
      breakdown.sort_by { |b| -b[:seconds] }
    end
  end

  private

  def handle_post_creation
    PostCreationToSlackJob.perform_later(self)
  end

  def update_project_duration_if_changed
    return unless saved_change_to_duration_seconds?

    post&.project&.recalculate_duration_seconds!
    Post::ShipEvent.recalculate_hours_for_devlog_post(post)
  end

  def update_devlogs_count_on_soft_delete
    return unless saved_change_to_deleted_at?

    project_id = post&.project_id
    return unless project_id

    delta = deleted_at.present? ? -1 : 1
    Project.unscoped.where(id: project_id).update_counters(devlogs_count: delta)

    # Keep cached duration_seconds accurate when devlogs are soft-deleted/restored.
    Project.unscoped.find_by(id: project_id)&.recalculate_duration_seconds!
    Post::ShipEvent.recalculate_hours_for_devlog_post(post)
  end
end
