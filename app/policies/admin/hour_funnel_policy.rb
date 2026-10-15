class Admin::HourFunnelPolicy < ApplicationPolicy
  # Admin only: the funnel totals every hour ever certified and every reviewer
  # verdict behind it, the same blast radius as the mega dashboard.
  def show? = user&.admin?

  def refresh? = show?
end
