module Admin
  class ApplicationController < ::ApplicationController
    include Pundit::Authorization

    before_action :prevent_admin_access_while_impersonating
    before_action :set_paper_trail_whodunnit
    after_action :verify_authorized

    def index
      authorize :admin
      if current_user.helper?
        redirect_to admin_support_path
      elsif current_user.fraud_dept? && !current_user.admin?
        redirect_to admin_fraud_path
      elsif current_user.shop_manager? && !current_user.admin?
        redirect_to admin_shop_path
      elsif current_user.has_role?(:raffle_admin) && !current_user.admin?
        redirect_to admin_raffles_path
      else
        redirect_to admin_users_path
      end
    end

    private

    def pundit_namespace(record)
      return record if record.is_a?(Array) && record.first == :admin

      [ :admin, record ]
    end

    def user_for_paper_trail
      impersonating? ? real_user&.id : current_user&.id
    end

    def prevent_admin_access_while_impersonating
      if impersonating?
        flash[:alert] = "You cannot access admin panels while impersonating. Stop impersonation first."
        redirect_to root_path
      end
    end
  end
end
