class Admin::Certification::IntegrityPolicy < ApplicationPolicy
  def index?
    user.admin? || user.has_role?(:fraud_lead)
  end

  def show?
    index?
  end

  def update?
    index?
  end
end
