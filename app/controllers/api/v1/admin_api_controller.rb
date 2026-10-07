# Public API endpoints that only admins may call. Authenticates with the
# admin's personal API key, like the rest of the public API.
class Api::V1::AdminApiController < Api::V1::PublicApiController
  before_action :require_admin!

  private
    def require_admin!
      render json: { error: "Admin access required" }, status: :forbidden unless current_api_user.admin?
    end
end
