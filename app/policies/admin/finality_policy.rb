class Admin::FinalityPolicy < ApplicationPolicy
  # Admin only: the page lists every shipper in the window and awarding moves
  # stardust.
  def show? = user&.admin?

  def award? = show?

  def freeze_pool? = show?
  def roll? = show?
  def reroll? = show?
end
