class Admin::ShopOrderPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.fraud_dept? || user&.shop_manager? || user&.fulfillment_person? || user&.helper?
  end

  def show?
    index?
  end

  def reveal_address?
    user&.admin? || user&.fraud_dept? || user&.fulfillment_person?
  end

  def reveal_phone?
    reveal_address?
  end

  def approve?
    user&.admin? || user&.fraud_dept?
  end

  def review_order?
    user&.admin? || user&.fraud_dept?
  end

  def reject?
    user&.admin? || user&.fraud_dept? || user&.fulfillment_person?
  end

  def update?
    user&.admin? || user&.fraud_dept? || user&.fulfillment_person?
  end

  def assign_user?
    user&.admin? || user&.fulfillment_person?
  end

  def manage?
    user&.admin?
  end

  def view_on_hold_state?
    user&.admin? || user&.fraud_dept? || user&.fulfillment_person? || user&.shop_manager?
  end
end
