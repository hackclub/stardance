class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern

  # Add Policy Pundit
  include Pundit::Authorization
  include Pagy::Method
  include Achievementable

  before_action :store_referral_code
  before_action :remember_page
  before_action :enforce_ban
  before_action :refresh_identity_on_portal_return
  before_action :initialize_cache_counters
  before_action :track_request
  before_action :track_active_user
  before_action :show_pending_achievement_notifications!
  before_action :apply_dev_override_ref
  before_action :allow_profiler

  # Track who makes changes in PaperTrail
  def user_for_paper_trail
    current_user&.id
  end

  rescue_from StandardError, with: :handle_error
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_auth_token
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def current_user(preloads = [])
    return @current_user if defined?(@current_user)

    if session[:user_id]
      scope = User.where(id: session[:user_id])
      scope = scope.eager_load(*Array(preloads)) if preloads.present?
      @current_user = scope.to_a.first
    end
  end
  helper_method :current_user
  helper_method :admin_policy

  def impersonating?
    session[:impersonator_user_id].present? && session[:user_id].present?
  end

  helper_method :impersonating?

  def real_user
    return nil unless session[:impersonator_user_id]
    @real_user ||= User.find_by(id: session[:impersonator_user_id])
  end

  helper_method :real_user

  def pundit_user
    impersonating? ? real_user : current_user
  end

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  # https://stackoverflow.com/questions/70960161/ruby-on-rails-back-button-that-will-take-you-back-to-the-previous-page
  # improvised a bit. a linked list sorta..
  def remember_page
    return unless request.get? && request.format.html?
    return if request.xhr?

    current_path = request.path
    pages = session[:previous_pages] ||= []

    if (idx = pages.index(current_path))
      session[:previous_pages] = pages[0..idx]
    elsif pages.last != current_path
      pages << current_path
      session[:previous_pages] = pages.last(10)
    end
  end

  def store_referral_code
    return unless params[:ref].present? && params[:ref].length <= 64

    cookies[:referral_code] = {
      value: params[:ref],
      expires: 30.days.from_now,
      same_site: :lax
    }
  end

  def render_not_found
    render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
  end

  def user_not_authorized(exception)
    if current_user.nil?
      store_return_to
      respond_to do |format|
        format.html { redirect_to root_path, alert: "Please sign in to continue." }
        format.json { render json: { error: "You must be signed in to do that." }, status: :unauthorized }
      end
      return
    end

    if current_user.guest?
      store_return_to
      respond_to do |format|
        format.turbo_stream { render "onboarding/upgrade_prompt", status: :forbidden }
        format.html { render "onboarding/upgrade_prompt", status: :forbidden, layout: "application" }
        format.json { render json: { error: "Sign in with Hack Club to do that." }, status: :forbidden }
      end
      return
    end

    @error_title = "Whoa there, explorer!"
    @error_message = exception.message.presence || "You don't have the right ingredients to access this page."
    @back_path = safe_referrer

    respond_to do |format|
      format.html { render "errors/not_authorized", status: :forbidden }
      format.json { render json: { error: @error_message }, status: :forbidden }
    end
  end

  # Skip oversized fullpaths so the cookie session can't overflow on long URLs.
  def store_return_to
    return unless request.get? || request.head?
    return if request.fullpath.bytesize > 1000

    session[:return_to] = request.fullpath
  end

  def safe_referrer
    return nil if request.referrer.blank?

    referrer_uri = URI.parse(request.referrer)
    return request.referrer if referrer_uri.host&.end_with?(".hackclub.com") || referrer_uri.host == "hackclub.com"

    nil
  rescue URI::InvalidURIError
    nil
  end

  def pundit_namespace(record)
    record
  end

  def authorize(record, ...)
    super(pundit_namespace(record), ...)
  end

  def policy_scope(scope, ...)
    super(pundit_namespace(scope), ...)
  end

  def policy(record)
    super(pundit_namespace(record))
  end

  def admin_policy(record)
    policy([ :admin, record ])
  end

  def handle_invalid_auth_token
    reset_session
    redirect_to root_path, alert: "Your session has expired. Please try again."
  end

  def handle_error(exception)
    event_id = Sentry.last_event_id || Sentry.capture_exception(exception)&.event_id
    @trace_id = event_id || request.request_id
    @exception = exception if current_user&.admin?

    raise exception if Rails.env.development? && !params[:show_error_page]

    respond_to do |format|
      format.html { render "errors/internal_server_error", status: :internal_server_error, layout: "application" }
      format.json { render json: { error: "Internal server error", trace_id: @trace_id }, status: :internal_server_error }
    end
  end

  def enforce_ban
    return unless current_user&.banned?
    return if controller_name == "home" || controller_name == "sessions"

    redirect_to home_path, alert: "Your account has been banned."
  end

  def initialize_cache_counters
    Thread.current[:cache_hits] = 0
    Thread.current[:cache_misses] = 0
  end

  def track_request
    RequestCounter.increment
  end

  def track_active_user
    ActiveUserTracker.track(user_id: current_user&.id, session_id: session.id.to_s)
  end

  def apply_dev_override_ref
    return unless Rails.env.development?
    return unless params[:_override_ref].present? && current_user
    return if params[:_override_ref].length > 64

    current_user.update!(ref: params[:_override_ref])
  end

  def allow_profiler
    return unless defined?(Rack::MiniProfiler)
    if current_user&.admin? || Rails.env.development?
      Rack::MiniProfiler.authorize_request
    end
  end

  def refresh_identity_on_portal_return
    return unless params[:portal_status].present? && current_user

    identity = current_user.identities.find_by(provider: "hack_club")
    return unless identity&.access_token.present?

    identity_payload = HCAService.identity(identity.access_token)
    return if identity_payload.blank?

    current_user.apply_hca_verification_payload!(identity_payload)
  rescue StandardError => e
    Rails.logger.warn("Portal return identity refresh failed: #{e.class}: #{e.message}")
  end
end
