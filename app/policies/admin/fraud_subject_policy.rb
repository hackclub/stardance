class Admin::FraudSubjectPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.fraud_lead? || user&.fraud_dept? || user&.fraud_fraud_squad_squad?
  end

  def show?
    index?
  end
end
