class GrowthPolicy < ApplicationPolicy
  def show? = true

  def rebuild? = user&.admin?
end
