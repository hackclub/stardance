class ShipFunnelPolicy < ApplicationPolicy
  def show? = true
  def refresh? = user&.admin?
  def live? = refresh?
end
