class Admin::MissionPolicy < ApplicationPolicy
  # Admin-only actions.
  def index?         = user_admin?
  def show?          = user_admin?
  def create?        = user_admin?
  def destroy?       = user_admin?
  def restore?       = user_admin?
  def manage_owners? = user_admin?

  # Shared with non-admin mission owners — the merged /admin/missions/:slug/edit
  # page and the admin/missions/* sub-resource CRUD. Delegates to the top-level
  # MissionPolicy, which already encodes owner-OR-admin semantics.
  def edit?   = manage?
  def update? = manage?

  def manage?
    mission = mission_record
    return false unless mission.is_a?(Mission)
    MissionPolicy.new(user, mission).manage?
  end

  private

  def user_admin? = user&.admin?

  # Admin::ApplicationController#pundit_namespace wraps records as
  # [:admin, record]; unwrap so MissionPolicy gets the bare Mission.
  def mission_record
    record.is_a?(Array) ? record.last : record
  end
end
