class Admin::SuperStarDashboardPolicy < ApplicationPolicy
  def show?
    user&.admin?
  end
end
