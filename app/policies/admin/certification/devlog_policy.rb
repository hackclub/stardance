class Admin::Certification::DevlogPolicy < ApplicationPolicy
  def update?
    user&.admin? || user&.has_role?(:guardian_of_integrity)
  end
end
