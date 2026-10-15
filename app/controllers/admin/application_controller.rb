module Admin
  class ApplicationController < ::ApplicationController
    include Pundit::Authorization

    layout "admin"

    before_action :prevent_admin_access_while_impersonating
    before_action :set_paper_trail_whodunnit
    after_action :verify_authorized

    def index
      authorize :admin
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
