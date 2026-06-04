class Project::MagicPolicy < ApplicationPolicy
  def create?
    user&.admin?
  end

  def destroy?
    user&.admin?
  end

  def nominate?
    user&.can_nominate_super_star?
  end

  def withdraw_nomination?
    user&.can_nominate_super_star?
  end
end
