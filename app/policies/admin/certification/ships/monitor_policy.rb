class Admin::Certification::Ships::MonitorPolicy < ApplicationPolicy
  def show? = user&.admin? || user&.super_admin?
end
