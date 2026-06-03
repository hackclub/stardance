# frozen_string_literal: true

# create? → reviewer can claim the ship
# destroy? → reviewer can unclaim the ship
class Admin::Certification::Ships::ClaimPolicy < ApplicationPolicy
  def create?
    user&.can_review? && not_own_project?
  end

  def destroy?
    return false unless user&.can_review? && not_own_project?

    record.claim_held_by?(user) || (record.reviewer_id == user.id && record.claim_expired?)
  end

  private

  def not_own_project?
    return true unless record.respond_to?(:project_id)

    !user.memberships.where(project_id: record.project_id).exists?
  end
end
