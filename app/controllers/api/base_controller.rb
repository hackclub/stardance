class Api::BaseController < ApplicationController
  include Pagy::Method

  skip_before_action :verify_authenticity_token
  skip_before_action :track_ahoy_visit, raise: false
  skip_after_action :set_ahoy_request_store, raise: false # TODO ???

  after_action :set_performance_headers
  after_action :set_request_id_headers

  rescue_from StandardError, with: :handle_err
  rescue_from ActiveRecord::RecordNotFound, with: :handle_404
  rescue_from ActiveRecord::RecordInvalid, with: :handle_bad

  MAX_LIMIT = 100

  private

  def api_limit
    limit = params.fetch(:limit, MAX_LIMIT).to_i
    if limit < 1 || limit > MAX_LIMIT
      render json: { error: "Limit must be between 1 and #{MAX_LIMIT}", request_id: request.request_id }, status: :bad_request
      return nil
    end
    limit
  end

  def handle_err(exception)
    # this will help with debugging
    Sentry.capture_exception(
      exception,
      extra: {
        request_id: request.request_id,
        user_id: respond_to?(:current_api_user) ? current_api_user&.id : nil, #TODO implement current_api_user
        endpoint: "#{request.method} #{request.path}",
        params: request.filtered_parameters,
        action: action_name
      },
      tags: {
        controller: controller_name,
        action: action_name
      }
    )

    render json: { error: "An unexpected error occurred", request_id: request.request_id }, status: :internal_server_error
  end

  def handle_404
    render json: { error: "Resource not found" }, status: :not_found
  end

  def handle_bad(exception)
    render json: { errors: exception.record.errors.full_messages }, status: :unprocessable_entity
  end

  def set_performance_headers
    response.set_header("X-DB-Queries", QueryCount::Counter.counter.to_s)
    response.set_header("X-DB-Cached", QueryCount::Counter.counter_cache.to_s)
    response.set_header("X-Cache-Hits", (Thread.current[:cache_hits] || 0).to_s)
    response.set_header("X-Cache-Misses", (Thread.current[:cache_misses] || 0).to_s)
  end

  def set_request_id_headers
    response.set_header("X-Request-ID", request.request_id)
  end
end