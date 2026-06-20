# frozen_string_literal: true

class Admin::Certification::ShipPolicy < ApplicationPolicy
  def index? = user&.can_review?

  def logs? = user&.can_review?

  def show? = user&.can_review? && not_own_project?

  def update? = show?

  def next? = user&.can_review?

  def set_project_type? = show?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.can_review?
      scope.joins(:project).where(projects: { deleted_at: nil })
    end
  end

  private

  def not_own_project?
    !user.memberships.exists?(project_id: record.project_id)
  end
end
