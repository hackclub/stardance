module ApiAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_key
  end

  private

  def authenticate_api_key
    auth = request.headers["Authorization"]

    unless auth&.starts_with?("Bearer ")
      render json: { error: "Missing or invalid Authorization header — use: Bearer YOUR_API_KEY", request_id: request.request_id }, status: :unauthorized
      return
    end

    token = auth.delete_prefix("Bearer ").strip

    unless token.present?
      render json: { error: "Missing API key", request_id: request.request_id }, status: :unauthorized
      return
    end

    @current_api_user = User.find_by(api_key: token)

    render json: { error: "Invalid API key", request_id: request.request_id }, status: :unauthorized unless @current_api_user
  end

  def current_api_user
    @current_api_user
  end
end
