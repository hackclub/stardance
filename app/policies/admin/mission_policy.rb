class Admin::MissionPolicy < ApplicationPolicy
  def index?
    manage?
  end

  def show?
    manage?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  def restore?
    manage?
  end

  private

  def manage?
    user&.admin?
  end
end
