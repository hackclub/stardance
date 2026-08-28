class Api::V1::PublicApiController < ActionController::API
  include Pagy::Method

  before_action :authenticate_api_user!

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  attr_reader :current_api_user

  private
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

    def bearer_token
      request.authorization.to_s[/\ABearer (.+)\z/, 1]
    end

    def render_not_found
      render json: { error: "Resource not found" }, status: :not_found
    end
end
