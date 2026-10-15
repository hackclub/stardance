class Admin::RatingDashboardPolicy < ApplicationPolicy
  def show? = user&.admin?
end
