class AdminPolicy < ApplicationPolicy
  def access_admin_dashboard?
    user.admin? || user.fraud_dept?
  end

  def index?
    user.admin? || user.fraud_dept? || user.shop_manager?
  end

  def access_blazer?
    user.admin?
  end

  def access_flipper?
    user.admin?
  end

  def manage_users?
    user.admin? || user.fraud_dept?
  end

  def manage_projects?
    user.admin? || user.fraud_dept?
  end

  def access_admin_endpoints?
    user.admin? || user.fraud_dept?
  end

  def manage_user_roles?
    user.admin? || user.super_admin?
  end

  def access_jobs?
    user.admin?
  end

  def manage_shop?
    user.admin?
  end

  def manage_draft_shop_items?
    user.admin? || user.shop_manager?
  end

  def view_shop_orders_no_pii?
    user.admin? || user.fraud_dept? || user.shop_manager?
  end

  def access_audit_logs?
    user.admin? || user.fraud_dept? || user.fulfillment_person?
  end

  def access_fulfillment_view?
    user.admin? || user.fulfillment_person?
  end

  def assign_shop_order?
    user.admin? || user.fulfillment_person?
  end

  def reject_shop_order?
    user.admin? || user.fraud_dept? || user.fulfillment_person?
  end

  def access_shop_orders?
    user.admin? || user.fraud_dept?
  end

  def access_payouts_dashboard?
    user.admin? || user.fraud_dept?
  end

  def access_fraud_dashboard?
    user.admin? || user.fraud_dept?
  end

  def access_fulfillment_dashboard?
    user.admin? || user.fulfillment_person?
  end

  def ban_users?
    user.admin? || user.fraud_dept?
  end

  def access_reports?
    user.admin? || user.fraud_dept?
  end

  def access_super_mega_dashboard?
    user.admin?
  end

  def access_voting_dashboard?
    user.admin? || user.fraud_dept?
  end

  def access_vote_spam_dashboard?
    user.admin? || user.fraud_dept?
  end

  def access_vote_quality_dashboard?
    user.admin? || user.fraud_dept?
  end

  def access_fulfillment_payouts?
    user.admin?
  end

  def approve_fulfillment_payouts?
    user.admin?
  end

  def access_shop_suggestions?
    user.admin?
  end

  def access_suspicious_votes?
    user.admin? || user.fraud_dept?
  end

  def manage_messages?
    user.admin?
  end

  def access_support_vibes?
    user.admin?
  end

  def access_sw_vibes?
    user.admin?
  end

  def access_special_activities?
    user.admin?
  end

  def access_flavortime_dashboard?
    user.admin? || user.flavortime?
  end
end
