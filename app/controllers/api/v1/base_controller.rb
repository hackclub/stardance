class Api::V1::BaseController < ActionController::API
  before_action :authenticate_api_key

  private
    def authenticate_api_key
      if valid_api_key?
        true
      else
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end

    def valid_api_key?
      if bearer_token.present? && api_keys.any?
        api_keys.any? do |api_key|
          if api_key.bytesize == bearer_token.bytesize
            ActiveSupport::SecurityUtils.secure_compare(api_key, bearer_token)
          else
            false
          end
        end
      else
        false
      end
    end

    def bearer_token
      request.authorization.to_s[/\ABearer (.+)\z/, 1]
    end

    def api_keys
      @api_keys ||= credential_api_keys.map(&:to_s).map(&:strip).select(&:present?)
    end

    def credential_api_keys
      Array.wrap(Rails.application.credentials.dig(:ambassador_referrals, :api_keys))
    end
end
