class Api::V1::CertificationDecisionsController < Api::V1::BaseController
  SIGNATURE_HEADER = "X-Shipwrights-Signature".freeze
  SIGNATURE_PREFIX = "sha256=".freeze
  MAX_BODY_BYTES = 64.kilobytes

  def create
    unless request.media_type == "application/json"
      return render json: { error: "expected application/json" }, status: :bad_request
    end

    payload = JSON.parse(request.raw_post)
    result = ExternalDashboard::DecisionProcessor.call(payload)
    render json: result.body, status: result.status
  rescue JSON::ParserError
    render json: { error: "malformed json" }, status: :bad_request
  end

  private

    def valid_api_key?
      return reject_auth("payload too large") if request.content_length.to_i > MAX_BODY_BYTES

      secret = ExternalDashboard::Client.decision_webhook_secret
      return reject_auth("secret not configured") if secret.blank?

      header = request.headers[SIGNATURE_HEADER].to_s.strip
      return reject_auth("missing signature header") if header.blank?
      return reject_auth("malformed signature header") unless header.start_with?(SIGNATURE_PREFIX)

      provided = header.delete_prefix(SIGNATURE_PREFIX).downcase
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)

      return true if ActiveSupport::SecurityUtils.secure_compare(expected, provided)
      reject_auth("signature mismatch")
    end

    def reject_auth(reason)
      Rails.logger.warn "[CertificationDecisions] rejected: #{reason}"
      false
    end
end
