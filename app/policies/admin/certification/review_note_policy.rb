# frozen_string_literal: true

class Admin::Certification::ReviewNotePolicy < ApplicationPolicy
  # Same bar as leaving a verdict: a hardware reviewer may add an internal note,
  # but never on a project they're a member of.
  def create? = can_review_hardware? && not_own_project?

  private

  def not_own_project?
    return true unless record.respond_to?(:project_id)
    !user.memberships.where(project_id: record.project_id).exists?
  end
end
