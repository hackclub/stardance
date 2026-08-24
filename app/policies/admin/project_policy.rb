class Admin::ProjectPolicy < ApplicationPolicy
  def index?
    user.admin? || user.fraud_dept? || user.helper? || user.nda_helper?
  end

  def show?
    index?
  end

  def view_votes?
    user.admin? || user.nda_helper?
  end

  def restore?
    user&.admin? || user&.fraud_dept?
  end

  def update?
    user&.admin? || user&.fraud_dept?
  end

  def destroy?
    user&.admin? || user&.fraud_dept?
  end
end
