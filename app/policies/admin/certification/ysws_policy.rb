class Admin::Certification::YswsPolicy < ApplicationPolicy
  def index?
    user.admin? || user.has_role?(:guardian_of_integrity)
  end

  def show?
    index?
  end

  def update?
    index?
  end

  def report_fraud?
    index?
  end
end
