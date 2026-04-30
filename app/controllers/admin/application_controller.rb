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

    # Shared admin dashboard logic
    def index
      authorize :admin, :index?
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
      elsif flavortime_dashboard_request? && policy(:admin).access_flavortime_dashboard?
        true
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
      return false unless controller_name == "shop_orders"

      case action_name
      when "index"
        # Allow access to index so controller can redirect to fulfillment view if needed
        true
      when "show", "reveal_address", "mark_fulfilled", "update_internal_notes", "assign_user", "reject"
        true
      else
        false
      end
    end

    def admin_dashboard_request?
      controller_name == "application" && action_name == "index"
    end

    def flavortime_dashboard_request?
      controller_name == "flavortime_dashboard"
    end

    def shop_manager_request?
      controller_name.in?(%w[shop_items shop_orders shop]) || admin_dashboard_request?
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
