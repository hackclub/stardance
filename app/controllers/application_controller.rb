class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern

  # Add Policy Pundit
  include Pundit::Authorization
  include Pagy::Method
  include Achievementable
  include Trackable
  include OutpostEmailing

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
  before_action :prepare_boot_splash

  # Track who makes changes in PaperTrail
  def user_for_paper_trail
    current_user&.id
  end

  rescue_from StandardError, with: :handle_error
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_auth_token
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  # Declares which discover-rail widgets render on this controller's pages, and
  # optionally the page context handed to them:
  #
  #   class MissionsController < ApplicationController
  #     discover_rail_widgets :mission_guide, :available_missions,
  #                           context: -> { { mission: @mission } }
  #   end
  #
  # Slugs are resolved against the widget registry (DiscoverRail::BaseWidget),
  # so naming a slug no widget has claimed is simply ignored. Subclasses that
  # stay silent inherit an empty rail.
  class_attribute :discover_rail_widget_slugs, default: [], instance_accessor: false
  class_attribute :discover_rail_context_proc, default: nil, instance_accessor: false

  def self.discover_rail_widgets(*slugs, context: nil)
    self.discover_rail_widget_slugs = slugs.map(&:to_sym)
    self.discover_rail_context_proc = context if context
  end

  def discover_rail_widgets
    self.class.discover_rail_widget_slugs
  end
  helper_method :discover_rail_widgets

  def discover_rail_context
    proc = self.class.discover_rail_context_proc
    proc ? instance_exec(&proc) : {}
  end
  helper_method :discover_rail_context

  def current_user(preloads = [])
    return @current_user if defined?(@current_user)

    if session[:user_id]
      scope = User.where(id: session[:user_id])
      scope = scope.eager_load(*Array(preloads)) if preloads.present?
      user = scope.to_a.first

      if user && session[:auth_level] != "hca" && user.hca_linked?
        reset_session
        return @current_user = nil
      end

      @current_user = user
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

  def sign_in_user(user, auth_level: "guest")
    session[:user_id] = user.id
    session[:auth_level] = auth_level
  end

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

  def client_ip_address
    request.headers["CF-Connecting-IP"].presence || request.remote_ip
  end

  def prepare_boot_splash
    @show_boot_splash = false
    return if controller_name == "landing"
    return unless request.get? && request.format.html?
    return if turbo_frame_request? || request.xhr?
    return if cookies[:stardance_booted].present?

    @show_boot_splash = true
    cookies[:stardance_booted] = { value: "1", same_site: :lax } # session cookie (cleared when the browser closes)
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
    @body_class = "error-page-body"
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found, layout: "application" }
      format.json { render json: { error: "Not found" }, status: :not_found }
      format.any { head :not_found }
    end
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

    render_not_authorized(exception)
  end

  def render_not_authorized(exception = nil)
    message = exception&.message.presence || "You don't have permission to access this page."

    respond_to do |format|
      format.html { render "errors/not_authorized", status: :forbidden, layout: "application" }
      format.json { render json: { error: message }, status: :forbidden }
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
    @body_class = "error-page-body"
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
    unless identity&.access_token.present?
      redirect_to "/auth/hack_club?origin=#{ERB::Util.url_encode(request.fullpath)}" and return
    end

    identity_payload = HCAService.identity(identity.access_token)
    if identity_payload.blank?
      flash.now[:alert] = "Couldn't reach the verification server. Try again in a moment."
      return
    end

    current_user.apply_hca_verification_payload!(identity_payload)
    current_user.reload

    return_path = request.path
    clean_params = request.query_parameters.except("portal_status")
    return_url = clean_params.any? ? "#{return_path}?#{clean_params.to_query}" : return_path

    if current_user.identity_verified?
      redirect_to return_url, notice: "You're verified — your work is now public!" and return
    else
      redirect_to "#{return_url}#{return_url.include?('?') ? '&' : '?'}idv_check=1" and return
    end
  rescue StandardError => e
    Rails.logger.warn("Portal return identity refresh failed: #{e.class}: #{e.message}")
    flash.now[:alert] = "Something went wrong checking your verification. Try again."
  end
end
