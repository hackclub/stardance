class Admin::MissionPolicy < ApplicationPolicy
  # Mission-admin actions: site admins plus the global mission_reviewer role,
  # which grants admin-equivalent control over every mission (including the
  # /admin/missions list and creating new missions) without site-wide admin.
  def index?         = mission_admin?
  def show?          = mission_admin?
  def create?        = mission_admin?
  def destroy?       = mission_admin?
  def restore?       = mission_admin?
  def manage_owners? = mission_admin?

  # Shared with non-admin mission owners — the merged /admin/missions/:slug/edit
  # page and the admin/missions/* sub-resource CRUD. Delegates to the top-level
  # MissionPolicy, which already encodes owner-OR-mission-admin semantics.
  def edit?   = manage?
  def update? = manage?

  def manage?
    mission = mission_record
    return false unless mission.is_a?(Mission)
    MissionPolicy.new(user, mission).manage?
  end

  # Reviewing a mission's queue: site admins, the global mission_reviewer role,
  # or a per-mission reviewer/owner membership (matches the submission queue's
  # accessible_mission? rule).
  def review?
    return true if mission_admin?
    mission = mission_record
    mission.is_a?(Mission) && mission.memberships.exists?(user_id: user&.id)
  end

  private

  def mission_admin? = user&.admin? || user&.mission_reviewer?

  # Admin::ApplicationController#pundit_namespace wraps records as
  # [:admin, record]; unwrap so MissionPolicy gets the bare Mission.
  def mission_record
    record.is_a?(Array) ? record.last : record
  end
end
