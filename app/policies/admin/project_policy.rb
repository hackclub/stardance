class Admin::ProjectPolicy < ApplicationPolicy
  def index?
    user.admin? || user.fraud_dept? || user.helper? || user.nda_helper?
  end

  def show?
    index?
  end

  def view_votes?
    user.admin? || user.helper? || user.nda_helper?
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

  def reset_devlogs?
    user&.admin?
  end

  def convert_to_software?
    user&.admin?
  end

  def block_shipping?
    unblock_shipping? && !record.hardware? && !record.deleted?
  end

  def unblock_shipping?
    user&.admin? || user&.super_admin?
  end
end
