class MissionPolicy < ApplicationPolicy
  def index? = true

  # Show page renders for all non-soft-deleted missions, even if windowed
  # outside the start/end range or disabled — historical and "coming soon"
  # links shouldn't 404. Soft-deleted missions remain hidden because the
  # default scope excludes them; this policy never sees them.
  def show? = true
  def gallery? = true
  def guide? = true

  def manage?
    return false unless user.present?
    return true if user.admin?
    # Owners can manage live missions only; once admin soft-deletes a mission,
    # ownership goes dormant until an admin restores it.
    return false if record.deleted_at?
    record.memberships.exists?(user_id: user.id, role: :owner)
  end

  # Admin-only sections of the merged /admin/missions/:slug/edit page:
  # slug rename, owner add/remove, and the danger zone (soft-delete / restore).
  # Non-admin owners can manage everything else, but ownership and the public
  # URL stay an admin prerogative.
  def manage_owners? = user&.admin?

  def destroy? = user&.admin?
end
