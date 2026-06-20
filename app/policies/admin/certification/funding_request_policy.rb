# frozen_string_literal: true

class Admin::Certification::FundingRequestPolicy < ApplicationPolicy
  def index? = user&.can_review?

  def show? = user&.can_review? && not_own_project?

  def update?
    return false unless user&.can_review? && not_own_project?
    record.claim_held_by?(user) || (record.reviewer_id == user.id && record.claim_expired?)
  end

  def next? = user&.can_review?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.can_review?
      scope.for_reviewer(user)
    end
  end

  private

  def not_own_project?
    return true unless record.respond_to?(:project_id)
    !user.memberships.where(project_id: record.project_id).exists?
  end
end
