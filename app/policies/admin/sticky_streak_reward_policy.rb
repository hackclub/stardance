class Admin::StickyStreakRewardPolicy < ApplicationPolicy
  def show? = user&.admin? || user&.shop_manager?

  def update? = show?
end
