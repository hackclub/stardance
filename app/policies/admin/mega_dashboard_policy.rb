class Admin::MegaDashboardPolicy < ApplicationPolicy
  # Admin only: the page aggregates every queue plus payout and spend figures,
  # so it deliberately doesn't follow the per-lane scoping the individual
  # queues use.
  def show? = user&.admin?

  def section? = show?

  def clear_cache? = show?
end
