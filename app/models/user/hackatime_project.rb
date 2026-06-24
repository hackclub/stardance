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

  private

  def enqueue_streak_resync
    user.update_column(:streak_synced_at, nil) if user.has_attribute?(:streak_synced_at)
    StreakSyncJob.perform_later(user_id)
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
