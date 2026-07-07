class Admin::UserPolicy < ApplicationPolicy
  def index?
    user&.admin? || user&.fraud_dept? || user&.helper?
  end

  def show?
    index?
  end

  def update?
    user&.admin? || user&.fraud_dept?
  end

  def impersonate?
    return false unless user&.admin? || user&.super_admin?
    return false if user.id == record.id
    return false if record.admin? && !user.super_admin?

    true
  end

  def stop_impersonating?
    user&.admin? || user&.super_admin?
  end

  def manage_roles?
    user&.admin? || user&.super_admin?
  end

  def ban?
    user&.admin? || user&.fraud_dept?
  end

  def manage_feature_flags?
    user&.admin?
  end

  def sync_hackatime?
    user&.admin? || user&.fraud_dept?
  end

  def refresh_verification?
    user&.admin? || user&.fraud_dept?
  end

  def reject_orders?
    user&.admin? || user&.fraud_dept?
  end

  def adjust_balance?
    return false unless user&.admin? || user&.fraud_dept?
    return false if protected_role?

    true
  end

  def cancel_grants?
    user&.admin? || user&.fraud_dept?
  end

  def set_vote_balance?
    user&.admin? || user&.fraud_dept?
  end

  def manage_ysws_override?
    user&.admin? || user&.fraud_dept?
  end

  def view_votes?
    user&.admin?
  end
  def view_order_full_details?
    user&.admin? || user&.fraud_dept? || user&.fulfillment_person? || user&.shop_manager?
  end

  def view_usd_cost?
    user&.admin? || user&.fulfillment_person? || user&.shop_manager?
  end

  def shop_order_action?
    user&.admin? || user&.fraud_dept?  || user&.fulfillment_person?
  end
  def view_fulfillment_info?
    user&.admin? || user&.fulfillment_person?
  end
  def view_email?
    user&.admin? || user&.fraud_dept?  || user&.fulfillment_person?
  end

  def view_internal_notes?
    user&.admin? || user&.fraud_dept?  || user&.fulfillment_person?
  end

  def audit_log?
    user&.admin? || user&.fraud_dept?
  end

  def unlink_identity?
    user&.admin?
  end

  private

  def protected_role?
    return false if user.has_role?(:super_admin) || user.has_role?(:admin)
    return true if record == user

    if user.has_role?(:fraud_dept)
      return true if record.has_role?(:admin) || record.has_role?(:super_admin)
    end

    protected_roles = [ :admin, :super_admin, :fraud_dept ]
    shared_protected_roles = user.roles & protected_roles & record.roles
    shared_protected_roles.any?
  end
end
