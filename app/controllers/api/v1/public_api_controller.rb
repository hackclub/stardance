class Api::V1::PublicApiController < ActionController::API
  include ApiAuthenticatable
  include ExtensionUsageTrackable
  include Pagy::Method

  before_action :authenticate_api_user!
  before_action :validate_limit!
  after_action :set_query_count_headers

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  PER_PAGE = 25
  MAX_PER_PAGE = 100

  attr_reader :current_api_user

  private
    # Pagy resolves :limit from the query string itself (the global
    # :client_max_limit in config/initializers/pagy.rb), so a raw params[:limit]
    # beats anything pre-clamped here — the cap has to reach Pagy as :max_limit.
    def pagination_options
      { limit: PER_PAGE, max_limit: MAX_PER_PAGE }
    end

    # Pagy raises on a limit below 1, so reject the values it can't take rather
    # than letting them 500.
    def validate_limit!
      raw = params[:limit]
      return if raw.blank?

      if !raw.to_s.match?(/\A\d+\z/) || raw.to_i.zero?
        render json: { error: "Limit must be a positive integer" }, status: :bad_request
      elsif raw.to_i > MAX_PER_PAGE
        render json: { error: "Limit cannot exceed #{MAX_PER_PAGE}" }, status: :bad_request
      end
    end

    def authenticate_api_user!
      unless bearer_token.present?
        return render json: { error: "Missing Authorization header" }, status: :unauthorized
      end

      @current_api_user = User.find_by(api_key: bearer_token)
      unless @current_api_user
        return render json: { error: "Invalid API key" }, status: :unauthorized
      end

      unless Flipper.enabled?(:"public_api_2026-08-28", @current_api_user)
        render json: { error: "API access is not enabled for your account" }, status: :forbidden
      end
    end

    def render_not_found
      render json: { error: "Resource not found" }, status: :not_found
    end

    def set_query_count_headers
      response.set_header("X-DB-Queries", QueryCount::Counter.counter.to_s)
      response.set_header("X-DB-Cached", QueryCount::Counter.counter_cache.to_s)
    end
end
