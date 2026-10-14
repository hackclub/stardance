class Admin::FraudSubjectPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.fraud_lead? || user&.fraud_dept?
  end

  def show?
    index?
  end
end
