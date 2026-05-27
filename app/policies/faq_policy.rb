class FaqPolicy < ApplicationPolicy
  def create?
    user&.admin? || user&.helper?
  end

  def update?
    user&.admin? || user&.helper?
  end

  def destroy?
    user&.admin? || user&.helper?
  end
end
