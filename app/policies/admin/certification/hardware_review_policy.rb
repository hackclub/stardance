# frozen_string_literal: true

# Authorizes the combined hardware review page. The record is the Project being
# reviewed. Same bar as the funding/ship review pages: the user must be a
# reviewer and must not own the project they're reviewing.
class Admin::Certification::HardwareReviewPolicy < ApplicationPolicy
  def index?
    user&.can_review?
  end

  # The design and build queues are the same permission as the old combined one.
  def design?
    index?
  end

  def build?
    index?
  end

  def next?
    index?
  end

  def show?
    user&.can_review? && not_own_project?
  end

  # Same bar as Certification::ShipPolicy#report_fraud?: any reviewer may flag,
  # including on a project they belong to (the fraud report skips the own-project
  # guard on purpose). Flagging notifies the fraud team; it doesn't decide the
  # review.
  def flag_for_fraud?
    user&.can_review?
  end

  private

  def not_own_project?
    !user.memberships.exists?(project_id: record.id)
  end
end
