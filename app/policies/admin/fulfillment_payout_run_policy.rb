class Admin::FulfillmentPayoutRunPolicy < ApplicationPolicy
  def index?
    user&.admin?
  end

  def show?
    index?
  end

  def approve?
    user&.admin?
  end

  def reject?
    user&.admin?
  end

  def trigger?
    user&.admin?
  end
end
