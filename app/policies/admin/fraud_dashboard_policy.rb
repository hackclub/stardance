class Admin::FraudDashboardPolicy < ApplicationPolicy
  def show?
    user&.admin? || user&.fraud_dept?
  end
end
