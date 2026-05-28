class Admin::ShopItemPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.shop_manager?
  end

  def show?
    index?
  end

  def create?
    index?
  end

  def new?
    create?
  end

  def update?
    index?
  end

  def destroy?
    user&.admin?
  end

  def manage?
    user&.admin?
  end
end
