class Admin::ShipFunnelPolicy < ApplicationPolicy
  def show? = user&.admin?
  def refresh? = show?
end
