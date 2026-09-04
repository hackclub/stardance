class Admin::Fraud::SubjectPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.fraud_lead? || user&.fraud_dept? || user&.fraud_squad?
  end

  def show?
    index?
  end
end
