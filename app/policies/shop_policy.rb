class ShopPolicy < ApplicationPolicy
  def index?
    signed_in_any?
  end

  def show?
    true
  end

  def create?
    signed_in_any?
  end

  def cancel?
    signed_in_any?
  end

  def destroy?
    signed_in_any?
  end
end
