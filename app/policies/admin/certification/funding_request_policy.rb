# frozen_string_literal: true

class Admin::Certification::FundingRequestPolicy < ApplicationPolicy
  def index? = user&.can_review?

  def show? = can_review_hardware? && not_own_project?

  def update?
    return false unless can_review_hardware? && not_own_project?
    record.claim_held_by?(user) || (record.reviewer_id == user.id && record.claim_expired?)
  end

  def next? = user&.can_review?

  # Same bar as a verdict: only the reviewer holding the claim may re-route it.
  def flag_queue_mismatch? = update?

  # Reversing a decided review is an admin-only correction: it rewinds a verdict
  # and can cancel a live HCB grant, so it sits above the ordinary reviewer bar.
  # Still never on your own project.
  def undo? = user&.admin? && not_own_project?

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
