class ShopSuggestionPolicy < ApplicationPolicy
  def index?
    true
  end

  def history?
    true
  end

  def create?
    signed_in_any?
  end
end
