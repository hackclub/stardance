class StickyStreakPolicy < ApplicationPolicy
  def start? = user.present?
end
