class Admin::SupportDashboardPolicy < ApplicationPolicy
  def show?
    user&.admin? || user&.fraud_dept? || user&.helper?
  end
end
