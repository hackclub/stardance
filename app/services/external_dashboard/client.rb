module ExternalDashboard
  module Client
    extend self

    DEFAULT_BASE_URL = "https://dash.shipwrights.dev".freeze
    ERROR_MESSAGE_MAX = 500
    DEFAULT_TIMEOUT_SECONDS = 10
    NOT_CONFIGURED_ERROR = "api key or workplace id missing".freeze
    STRICT_INTEGER_PATTERN = /\A\d+\z/
    EXTERNAL_ID_PATTERN = /\A\d{1,32}\z/

    def configured?
      api_key.present? && workplace_id.present?
    end

    def parse_json(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end

    def error_from(body)
      body["error"].to_s.truncate(ERROR_MESSAGE_MAX).presence
    end

    def decision_webhook_secret
      raw = Rails.application.credentials.dig(:external_dashboard, :decision_webhook_secret).presence ||
            ENV["EXTERNAL_REVIEW_SECRET"].presence
      raw.is_a?(String) ? raw : nil
    end

    def base_url
      Rails.application.credentials.dig(:external_dashboard, :base_url) ||
        ENV["EXTERNAL_DASHBOARD_BASE_URL"].presence ||
        DEFAULT_BASE_URL
    end

    def certification_url(uuid)
      return if uuid.blank?
      "#{base_url}/stardance/certifications/#{uuid}"
    end

    def api_key
      Rails.application.credentials.dig(:external_dashboard, :api_key) ||
        ENV["EXTERNAL_DASHBOARD_API_KEY"]
    end

    def workplace_id
      Rails.application.credentials.dig(:external_dashboard, :workplace_id) ||
        ENV["EXTERNAL_DASHBOARD_WORKPLACE_ID"]
    end

    def connection(timeout: DEFAULT_TIMEOUT_SECONDS)
      Faraday.new(url: base_url) do |conn|
        conn.options.timeout = timeout
        conn.options.open_timeout = timeout
        conn.headers["Content-Type"] = "application/json"
        conn.headers["x-api-key"] = api_key.to_s
        conn.headers["x-workplace-id"] = workplace_id.to_s
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
