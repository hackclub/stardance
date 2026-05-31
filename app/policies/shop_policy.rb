class ShopPolicy < ApplicationPolicy
  def index?
    signed_in_any?
  end

  def show?
    signed_in_any?
  end

  def create?
    signed_in_any?
  end

  def cancel?
    signed_in_any?
  end
end
