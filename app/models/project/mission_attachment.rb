# == Schema Information
#
# Table name: project_mission_attachments
#
#  id          :bigint           not null, primary key
#  attached_at :datetime         not null
#  deleted_at  :datetime
#  detached_at :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  mission_id  :bigint           not null
#  project_id  :bigint           not null
#
# Indexes
#
#  index_project_mission_attachments_active         (project_id,mission_id) UNIQUE WHERE ((detached_at IS NULL) AND (deleted_at IS NULL))
#  index_project_mission_attachments_on_deleted_at  (deleted_at)
#  index_project_mission_attachments_on_mission_id  (mission_id)
#  index_project_mission_attachments_on_project_id  (project_id)
#  index_project_mission_attachments_one_active     (project_id) UNIQUE WHERE ((detached_at IS NULL) AND (deleted_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (project_id => projects.id)
#
class Project::MissionAttachment < ApplicationRecord
  self.table_name = "project_mission_attachments"

  include SoftDeletable

  has_paper_trail

  belongs_to :project, inverse_of: :mission_attachments
  belongs_to :mission

  scope :active, -> { where(detached_at: nil) }

  validates :attached_at, presence: true

  validate :project_unshipped_or_follow_up, on: :create
  validate :no_other_active_attachment, on: :create
  validate :hardware_mission_takes_hardware_project, on: :create

  before_validation :default_attached_at, on: :create

  # Both detaching and switching missions come through here. Only a trusted
  # admin action may bypass the review lock; never pass a request parameter.
  def detach!(force: false)
    return if detached_at.present?

    transaction do
      if project.hardware_review_pending? && !force
        errors.add(:base, "You can't detach or switch missions while your hardware project is under review.")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(detached_at: Time.current)
      discard_rejected_submissions
    end
  end

  private

  # Leaving a mission also clears the reviews it failed: the rejected
  # submissions come off their ships, so those ships stop blocking the next
  # one (see Project#blocking_mission_submission) and read as plain ships.
  def discard_rejected_submissions
    project.mission_submissions.rejected.where(mission_id: mission_id).find_each(&:soft_delete!)
  end

  def default_attached_at
    self.attached_at ||= Time.current
  end

  # v1 policy: a project can have at most one active mission attachment.
  # Schema permits many; the app code is the gate. Skipped when the shipped
  # check above already failed — one clear message beats two stacked ones.
  def no_other_active_attachment
    return if errors[:base].any?
    return unless project_id

    other = self.class.where(project_id: project_id, detached_at: nil).where.not(id: id)
    return unless other.exists?

    errors.add(:base, "Detach the current mission before attaching another")
  end

  # Shipped projects keep their mission, except to continue into a follow-up
  # or to restore a mission they shipped to. Single source for the rule:
  # Project#may_swap_mission_to?.
  def project_unshipped_or_follow_up
    return unless project_id && project
    return if project.may_swap_mission_to?(mission)

    errors.add(:base, "Can't attach a mission to a project that has already shipped")
  end

  # Hardware missions only accept hardware projects (Mission#hardware?). The
  # builder switches their project to hardware on the project page first.
  def hardware_mission_takes_hardware_project
    return unless project && mission&.hardware?
    return if project.hardware?

    errors.add(:base, "#{mission.name} is a hardware mission — switch your project to hardware before attaching.")
  end
end
