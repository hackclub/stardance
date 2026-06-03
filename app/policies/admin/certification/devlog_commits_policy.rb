class Admin::Certification::DevlogCommitsPolicy < ApplicationPolicy
  def index?
    user.admin? || user.has_role?(:guardian_of_integrity)
  end
end
