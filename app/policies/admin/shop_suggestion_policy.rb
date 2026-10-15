class Admin::ShopSuggestionPolicy < ApplicationPolicy
  def accept?
    user&.admin?
  end

  def reject?
    user&.admin?
  end

  def delete?
    user&.admin?
  end
end
