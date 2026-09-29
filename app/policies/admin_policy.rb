class AdminPolicy < ApplicationPolicy
  def index?
    user.roles.any?
  end

  def access_funnel?
    user.admin? || user.fraud_dept? || user.shop_manager? || user.helper?
  end

  def access_blazer?
    user.admin?
  end

  def access_flipper?
    user.admin?
  end

  def manage_buku_event?
    user&.admin?
  end

  def access_jobs?
    user.admin?
  end

  def view_leaderboard?
    user.admin? || user.fulfillment_person? || user.fraud_dept?
  end

  def view_fraud_review_filters?
    user.admin? || user.fraud_dept?
  end

  def access_raffles?
    user.admin? || user.has_role?(:raffle_admin)
  end

  def access_workshops?
    user.admin? || user.workshop_manager?
  end

  def access_email_templates?
    user.admin?
  end

  def manage_shop?
    user.admin? || user.shop_manager?
  end

  def manage_draft_shop_items?
    user.admin? || user.shop_manager?
  end

  def import_devlogs?
    user.admin?
  end
end
