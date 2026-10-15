# app/models/user/hackatime_project.rb
# == Schema Information
#
# Table name: user_hackatime_projects
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  project_id :bigint
#  user_id    :bigint           not null
#
# Indexes
#
#  index_user_hackatime_projects_on_project_id        (project_id)
#  index_user_hackatime_projects_on_user_id           (user_id)
#  index_user_hackatime_projects_on_user_id_and_name  (user_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (user_id => users.id)
#
class User::HackatimeProject < ApplicationRecord
  include FunnelResyncTrigger

  has_paper_trail

  belongs_to :user
  belongs_to :project, optional: true

  EXCLUDED_NAMES = [ "Other", "<<LAST_PROJECT>>" ].freeze

  validates :name, presence: true
  # this ensures that the key can be used in js 1 project
  validates :name, uniqueness: { scope: :user_id }
  validates :name, exclusion: { in: EXCLUDED_NAMES, message: "is excluded" }
  validate :project_not_already_linked, if: :project_id_changed?
  validate :not_used_in_devlog, if: :project_id_changed?

  after_commit :enqueue_streak_resync, if: -> { saved_change_to_project_id? && project_id.present? }
  after_commit :resync_project_devlogs_later, on: %i[create update], if: -> { saved_change_to_project_id? && project_id.present? }

  # Point `name` at `project` for `user`, so time logged under that Hackatime
  # project counts toward the Stardance project. Idempotent on (user, name), and
  # never steals a name already linked to a different Stardance project; in that
  # case the existing link is left alone. Best-effort: callers link as a
  # side-effect of work that has already succeeded, so a validation failure here
  # shouldn't take that work down with it.
  def self.link(user:, project:, name:)
    record = find_or_initialize_by(user: user, name: name)
    return record if record.persisted? && record.project_id.present? && record.project_id != project.id

    record.project = project
    record.save
    record
  rescue ActiveRecord::RecordNotUnique
    # (user_id, name) is unique and this is check-then-act, so concurrent runs
    # can both miss the lookup and both insert. The loser just reads back the
    # row the winner created rather than taking the whole caller down.
    find_by(user: user, name: name)
  end

  private
    def enqueue_streak_resync
      user.update_column(:streak_synced_at, nil) if user.has_attribute?(:streak_synced_at)
      StreakSyncJob.perform_later(user_id)
    end

    def resync_project_devlogs_later
      project.resync_devlogs_from_hackatime_later
    end

    def project_not_already_linked
      return if project_id.nil? # Allow unlinking (setting project to nil)
      return unless project_id_was.present? && project_id_was != project_id

      previous_project = Project.unscoped.find_by(id: project_id_was)
      return if previous_project.nil? || previous_project.deleted?

      errors.add(:project, "is already linked to another project")
    end

    def not_used_in_devlog
      return unless project_id_was.present? && project_id != project_id_was

      previous_project = Project.unscoped.find_by(id: project_id_was)
      return if previous_project.nil?

      devlog_uses_key = previous_project.posts
        .joins("INNER JOIN post_devlogs ON post_devlogs.id = posts.postable_id AND posts.postable_type = 'Post::Devlog'")
        .where("post_devlogs.hackatime_projects_key_snapshot LIKE ?", "%#{name}%")
        .exists?

      if devlog_uses_key
        errors.add(:base, "cannot be unlinked because it was used in a devlog")
      end
    end
end
