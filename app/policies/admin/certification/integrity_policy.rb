class Admin::Certification::IntegrityPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.fraud_lead? || user&.fraud_fraud_squad_squad?
  end

  def show?
    index?
  end

  def update?
    index?
  end
end
