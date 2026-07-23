class WorkshopPolicy < ApplicationPolicy
  def index?
    logged_in?
  end

  def show?
    logged_in?
  end

  def rsvp?
    logged_in?
  end

  def join?
    logged_in?
  end

  def manage?
    user.present? && (user.admin? || user.workshop_manager?)
  end
end
