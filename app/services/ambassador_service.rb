# frozen_string_literal: true

class AmbassadorService
  class << self
    def enabled? = data_access_key.present?

    def expeditions
      return nil unless enabled?

      response = connection.get("/api/stardance/expeditions")
      return Array(response.body["expeditions"]) if response.success? && response.body.is_a?(Hash)

      Rails.logger.error "Ambassador API /api/stardance/expeditions failed: HTTP #{response.status}"
      nil
    rescue Faraday::Error => error
      Rails.logger.error "Ambassador API request failed: #{error.message}"
      nil
    end

    private

    def data_access_key = Rails.application.credentials.dig(:ambassador, :data_access_key)

    def api_url = ENV.fetch("AMBASSADOR_API_URL", "https://ambassador.hackclub.com")

    def connection
      @connection ||= Faraday.new(url: api_url) do |faraday|
        faraday.request :url_encoded
        faraday.headers["X-Stardance-Data-Access-Key"] = data_access_key
        faraday.response :json
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
