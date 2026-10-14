# == Schema Information
#
# Table name: project_memberships
#
#  id         :bigint           not null, primary key
#  role       :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  project_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_project_memberships_on_project_id              (project_id)
#  index_project_memberships_on_project_id_and_user_id  (project_id,user_id) UNIQUE
#  index_project_memberships_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (user_id => users.id)
#
class Project::Membership < ApplicationRecord
  include FunnelResyncTrigger

  has_paper_trail

  belongs_to :user
  belongs_to :project, counter_cache: :memberships_count

  enum :role, { owner: 0, contributor: 1 }, default: :owner # owners can add or remove people. contributors can't. that's the only diff

  validates :user_id, uniqueness: { scope: :project_id }
  validate :member_limit, on: :create

  # Someone joining a project that is already hardware needs their own Hackatime
  # project to record Lapse timelapses against, the same as the members who were
  # here when it turned hardware. The job re-checks every member, which is cheap
  # because members who already have one are skipped.
  #
  # Skipped for the very first membership, which is the owner being attached
  # during project creation: Project's own after_commit already covers that, and
  # enqueuing twice just makes two workers redo the same work.
  after_commit :ensure_hackatime_project, on: :create,
               if: -> { project&.hardware? && project.memberships.count > 1 }

  private

  def ensure_hackatime_project
    Project::EnsureHackatimeProjectsJob.perform_later(project_id)
  end

  def member_limit
    return unless project

    if project.memberships_count >= 3
      errors.add(:base, "Project can have at most 3 users.")
    end
  end
end
