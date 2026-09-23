# frozen_string_literal: true

# T2 hardware review: project_certifier isn't enough, a different reviewer clears the payout.
class Admin::Certification::SecondStageReviewPolicy < ApplicationPolicy
  def index? = second_stage_reviewer?

  def design? = index?
  def build? = index?
  def next? = index?

  def show? = second_stage_reviewer? && not_own_project?

  def skip? = show?

  # The T1 reviewer can't hold the claim, or they'd block everyone until it expired.
  def claim? = second_stage_reviewer? && not_own_project? && not_own_first_stage?

  # Pending only: re-deciding would return a submission whose payout already went out.
  def update?
    return false unless record.pending? && claim?

    record.claim_held_by?(user) || (record.reviewer_id == user.id && record.claim_expired?)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.has_role?(:t2_reviewer) || user&.admin?

      scope.for_reviewer(user)
    end
  end

  private

  def second_stage_reviewer?
    user.present? && (user.has_role?(:t2_reviewer) || user.admin?)
  end

  def not_own_first_stage?
    record.reviewable&.reviewer_id != user.id
  end

  def not_own_project?
    project_id = record.reviewable&.project_id
    return true if project_id.blank?

    !user.memberships.where(project_id: project_id).exists?
  end
end
