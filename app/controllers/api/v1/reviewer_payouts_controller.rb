class Api::V1::ReviewerPayoutsController < Api::V1::BaseController
  API_KEY_HEADER = "x-api-key".freeze
  WORKPLACE_ID_HEADER = "x-workplace-id".freeze
  MAX_BODY_BYTES = 64.kilobytes

  def index
    result = ExternalDashboard::ReviewerPayoutStatusProcessor.call(slack_id: params[:slackId])
    render json: result.body, status: result.status
  end

  def all
    render json: ExternalDashboard::ReviewerPayoutBulkStatusProcessor.call
  end

  def create
    result = ExternalDashboard::ReviewerPayoutCreationProcessor.call(parsed_body)
    render json: result.body, status: result.status
  rescue JSON::ParserError
    render json: { error: "malformed json" }, status: :bad_request
  end

  def decision
    result = ExternalDashboard::ReviewerPayoutDecisionProcessor.call(params[:id], parsed_body)
    render json: result.body, status: result.status
  rescue JSON::ParserError
    render json: { error: "malformed json" }, status: :bad_request
  end

  private

    def parsed_body
      JSON.parse(request.raw_post)
    end

    def valid_api_key?
      return reject_auth("payload too large") if request.content_length.to_i > MAX_BODY_BYTES

      expected_key = ExternalDashboard::Client.api_key.to_s
      return reject_auth("api key not configured") if expected_key.blank?
      return reject_auth("missing or invalid api key") unless secure_equal?(expected_key, request.headers[API_KEY_HEADER].to_s)

      expected_workplace_id = ExternalDashboard::Client.workplace_id.to_s
      return reject_auth("workplace id not configured") if expected_workplace_id.blank?
      return reject_auth("missing or invalid workplace id") unless secure_equal?(expected_workplace_id, request.headers[WORKPLACE_ID_HEADER].to_s)

      true
    end

    def secure_equal?(expected, provided)
      provided.present? && expected.bytesize == provided.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(expected, provided)
    end

    def reject_auth(reason)
      Rails.logger.warn "[ReviewerPayouts] rejected: #{reason}"
      false
    end
end
