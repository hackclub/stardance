# Talks to Lookout (Hack Club's screen-recording time tracker).
# See https://github.com/hackclub/lookout/blob/main/docs/integration.md
#
# Session creation is server-to-server (X-API-Key). Once a session exists, the
# browser drives recording against the token-authenticated client API, and we
# poll the same client API server-side to mirror status/duration/video back into
# our LookoutSession row. Lookout forwards the recording to Hackatime as a
# project named after `projectName`, which the user then links like any other
# Hackatime project.
class LookoutService
  BASE_URL = Rails.application.credentials.dig(:lookout, :base_url) || ENV.fetch("LOOKOUT_BASE_URL", "https://lookout.hackclub.com")
  API_KEY  = Rails.application.credentials.dig(:lookout, :api_key) || ENV.fetch("LOOKOUT_API_KEY", "")

  class << self
    # Server-to-server. Returns the parsed body ({ token:, sessionId:,
    # sessionUrl: }) or nil on failure.
    def create_session(user_id:, project_id:, project_name:)
      response = internal_connection.post("api/internal/sessions") do |req|
        req.body = {
          metadata: {
            userId: user_id,
            projectId: project_id,
            projectName: project_name
          }
        }.to_json
      end

      if response.success?
        JSON.parse(response.body).symbolize_keys
      else
        Rails.logger.error "LookoutService create_session error: #{response.status} - #{response.body}"
        nil
      end
    rescue => e
      Rails.logger.error "LookoutService create_session exception: #{e.message}"
      nil
    end

    # Client API (token-authenticated). Status/duration/video for polling.
    def fetch_session(token)
      response = client_connection.get("api/sessions/#{token}")

      if response.success?
        JSON.parse(response.body).symbolize_keys
      else
        Rails.logger.error "LookoutService fetch_session error: #{response.status}"
        nil
      end
    rescue => e
      Rails.logger.error "LookoutService fetch_session exception: #{e.message}"
      nil
    end

    # Capture timestamps for a finished session, forwarded to Hackatime as
    # heartbeats. Returns the parsed body (an array, or a hash with a
    # "timestamps" key) or nil.
    def fetch_timings(token)
      response = client_connection.get("api/sessions/#{token}/timings")

      if response.success?
        JSON.parse(response.body)
      else
        Rails.logger.error "LookoutService fetch_timings error: #{response.status}"
        nil
      end
    rescue => e
      Rails.logger.error "LookoutService fetch_timings exception: #{e.message}"
      nil
    end

    def stop_session(token)
      response = client_connection.post("api/sessions/#{token}/stop")

      if response.success?
        JSON.parse(response.body).symbolize_keys
      else
        Rails.logger.error "LookoutService stop_session error: #{response.status}"
        nil
      end
    rescue => e
      Rails.logger.error "LookoutService stop_session exception: #{e.message}"
      nil
    end

    # The hosted recorder URL the browser opens to record a session. Derived
    # from the token so we don't need to persist sessionUrl.
    def session_url_for(token)
      "#{BASE_URL}/session?token=#{token}"
    end

    private

    def internal_connection
      @internal_connection ||= Faraday.new(url: BASE_URL) do |conn|
        conn.headers["Content-Type"] = "application/json"
        conn.headers["X-API-Key"] = API_KEY
        conn.adapter Faraday.default_adapter
      end
    end

    def client_connection
      @client_connection ||= Faraday.new(url: BASE_URL) do |conn|
        conn.headers["Content-Type"] = "application/json"
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
