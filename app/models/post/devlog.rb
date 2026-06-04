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
  include SemanticSearchIndexable
  has_paper_trail ignore: [ :likes_count, :comments_count, :hackatime_pulled_at, :synced_at ]
  semantic_search_indexable type: "devlog"

  # Ignore devlog_review_id column before removing it in migration
  self.ignored_columns += [ "devlog_review_id" ]

  BODY_MAX_LENGTH = 4_000
  MAX_ATTACHMENTS = 4
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

  private

  def handle_post_creation
    PostCreationToSlackJob.perform_later(self)
  end

  def update_project_duration_if_changed
    return unless saved_change_to_duration_seconds?

    post&.project&.recalculate_duration_seconds!
  end

  def update_devlogs_count_on_soft_delete
    return unless saved_change_to_deleted_at?

    project_id = post&.project_id
    return unless project_id

    delta = deleted_at.present? ? -1 : 1
    Project.unscoped.where(id: project_id).update_counters(devlogs_count: delta)

    # Keep cached duration_seconds accurate when devlogs are soft-deleted/restored.
    Project.unscoped.find_by(id: project_id)&.recalculate_duration_seconds!
  end
end
