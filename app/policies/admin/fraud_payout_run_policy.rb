class Admin::FraudPayoutRunPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.fraud_dept?
  end

  def show?
    index?
  end

  def approve?
    user&.admin?
  end

  def reject?
    user&.admin?
  end

  def trigger?
    user&.admin?
  end
end
