# app/controllers/admin/application_controller.rb
module Admin
  class ApplicationController < ::ApplicationController
    include Pundit::Authorization

    layout "admin"

    # Rescue all Pundit authorization errors
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    # Optional before_action to enforce admin/fraud dept on all admin controllers
    before_action :prevent_admin_access_while_impersonating
    before_action :authenticate_admin, unless: :mission_control_jobs?
    before_action :set_paper_trail_whodunnit

    def index
      authorize :admin, :index?
      redirect_to admin_users_path
    end

    private

    # Use this to protect all admin endpoints
    def authenticate_admin
      # Must be logged in
      unless current_user
        redirect_to root_path, alert: "Please log in first" and return
      end

      # Fulfillment people can only access the shop orders fulfillment endpoint
      # But admins can access everything
      if current_user.fulfillment_person? && !current_user.admin? && !current_user.fraud_dept?
        unless shop_orders_fulfillment?
          raise Pundit::NotAuthorizedError
        end
      elsif shop_manager_request? && current_user.shop_manager?
        true
      else
        authorize :admin, :access_admin_endpoints?  # calls AdminPolicy#access_admin_endpoints?
      end
    end

    def mission_control_jobs?
      request.path.start_with?("/admin/jobs")
    end

    def shop_orders_fulfillment?
      case controller_name
      when "shop_orders"
        action_name.in?(%w[index show reveal_address mark_fulfilled update_internal_notes assign_user reject reveal_phone])
      when "shop_items"
        action_name == "show"
      else
        false
      end
    end

    def shop_manager_request?
      controller_name.in?(%w[application shop_items shop_orders shop])
    end

    # Handles unauthorized access
    def user_not_authorized
      flash[:alert] = "Hey there buddy u aint no admin!"
      redirect_to(request.referrer || root_path)
    end

    # Track who makes changes in PaperTrail
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
