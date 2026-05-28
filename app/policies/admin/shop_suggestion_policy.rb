class Admin::ShopSuggestionPolicy < ApplicationPolicy
  def index?
    user&.admin?
  end

  def destroy?
    user&.admin?
  end

  def update?
    user&.admin?
  end
end
