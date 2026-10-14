class Mission::SubmissionPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.blank?
      return scope.all if user.admin? || user.has_role?(:mission_reviewer)

      scope.where(mission_id: user.mission_memberships.select(:mission_id))
    end
  end

  def index?
    return false unless user.present?
    user.admin? || user.has_role?(:mission_reviewer) ||
      user.mission_memberships.exists?
  end

  # Show: admin / mission reviewer / per-mission member / submitter / helper.
  def show?
    return false unless user.present?
    return true if user.admin?
    return true if user.has_role?(:helper)
    return true if user.has_role?(:mission_reviewer)
    return true if per_mission_membership?
    submitter?
  end

  def review?
    return false unless user.present?
    return false if submitter_or_teammate?

    user.admin? || user.has_role?(:mission_reviewer) || per_mission_membership?
  end

  alias_method :approve?, :review?
  alias_method :reject?, :review?
  alias_method :undo?, :review?
  alias_method :update?, :review?
  alias_method :claim?, :review?

  def redeem?
    return false unless user.present?
    submitter? && record.approved? && record.prizes_to_claim?
  end

  private

  def per_mission_membership?
    record.mission.memberships.exists?(user_id: user.id)
  end

  def submitter?
    record.ship_event&.post&.user_id == user.id
  end

  def submitter_or_teammate?
    return false unless record.ship_event&.post&.project
    record.ship_event.post.project.users.exists?(id: user.id)
  end
end
