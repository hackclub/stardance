# frozen_string_literal: true

class AmbassadorService
  class << self
    def enabled? = ENV["AMBASSADOR_DATA_ACCESS_KEY"].present?

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

    def api_url = ENV.fetch("AMBASSADOR_API_URL", "https://ambassador.hackclub.com")

    def connection
      @connection ||= Faraday.new(url: api_url) do |faraday|
        faraday.request :url_encoded
        faraday.headers["X-Stardance-Data-Access-Key"] = ENV["AMBASSADOR_DATA_ACCESS_KEY"]
        faraday.response :json
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
