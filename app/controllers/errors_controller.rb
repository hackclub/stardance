class ErrorsController < ApplicationController
  skip_before_action :store_referral_code,
                     :remember_page,
                     :enforce_ban,
                     :refresh_identity_on_portal_return,
                     :initialize_cache_counters,
                     :track_request,
                     :track_active_user,
                     :show_pending_achievement_notifications!,
                     :apply_dev_override_ref,
                     :allow_profiler,
                     raise: false

  def bad_request
    render_error "errors/bad_request", 400
  end

  def not_found
    render_not_found
  end

  def not_acceptable
    render_error "errors/not_acceptable", 406
  end

  def unprocessable_entity
    render_error "errors/unprocessable_entity", 422
  end

  def internal_server_error
    handle_error(request.env["action_dispatch.exception"] || RuntimeError.new("Internal Server Error"))
  end

  private

  def render_error(template, status)
    @body_class = "error-page-body"
    respond_to do |format|
      format.html { render template, status: status, layout: "application" }
      format.json { render json: { error: Rack::Utils::HTTP_STATUS_CODES[status] }, status: status }
      format.any  { head status }
    end
  end
end
