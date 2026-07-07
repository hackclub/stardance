class UserPolicy < ApplicationPolicy
  def show?
    true
  end

  def update?
    user.present? && user.id == record.id
  end

  def follow?
    user.present? && user.hca_linked? && user.id != record.id
  end

  def followers?
    true
  end

  def following?
    true
  end
end
