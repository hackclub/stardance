# Talks to Lapse (Hack Club's timelapse recorder — https://api.lapse.hackclub.com).
#
# Used by hardware funding review to surface the timelapses a builder recorded
# *for the project under review* — not their whole library. Authenticates
# server-to-server with a Lapse program key (Bearer), scoped to
# `timelapse:read`/`snapshot:read`.
#
# Lapse ties each timelapse to a Hackatime project key, so the join is:
# our Project's Hackatime keys (Project#hackatime_keys) + the submitter's
# Hackatime id → `hackatime.timelapsesForProject`.
class LapseService
  BASE_URL = Rails.application.credentials.dig(:lapse, :base_url) || ENV.fetch("LAPSE_BASE_URL", "https://api.lapse.hackclub.com")
  # Where builders go to actually record. Lapse takes no deep-link parameters
  # (its index reads only an `error` param), so we send them to the root and they
  # pick the Hackatime project there: the one Project::EnsureHackatimeProjectsJob
  # seeded when the project turned hardware.
  APP_URL = Rails.application.credentials.dig(:lapse, :app_url) || ENV.fetch("LAPSE_APP_URL", "https://lapse.hackclub.com")
  API_KEY  = Rails.application.credentials.dig(:lapse, :api_key) || ENV.fetch("LAPSE_API_KEY", "")

  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 6
  # Safety cap so a project with an unusually long key list can't fan out into
  # an unbounded number of upstream requests on a review page load.
  MAX_KEYS = 12

  class << self
    # Timelapses the given Hackatime user recorded against any of `project_keys`
    # (a project can link more than one Hackatime key). Returns an array of
    # timelapse hashes (symbolized top-level keys), deduplicated by id and
    # ordered newest-first, or [] when inputs are blank or the API is
    # unreachable. Never raises — review pages must render regardless.
    #
    # Keys are fetched concurrently: each is an independent upstream call, so
    # wall-clock stays ~one request instead of N, keeping a slow/unreachable
    # Lapse from stacking timeouts and hanging the web worker.
    def timelapses_for_project(hackatime_user_id:, project_keys:)
      return [] if hackatime_user_id.blank? || project_keys.blank? || API_KEY.blank?

      keys = Array(project_keys).reject(&:blank?).uniq.first(MAX_KEYS)
      return [] if keys.empty?

      keys
        .map { |key| Thread.new { timelapses_for_project_key(hackatime_user_id, key) } }
        .flat_map(&:value)
        .uniq { |tl| tl[:id] }
        .sort_by { |tl| -tl[:createdAt].to_i }
    end

    private

    # GET /hackatime/timelapsesForProject — one Hackatime project key's timelapses.
    def timelapses_for_project_key(hackatime_user_id, project_key)
      response = connection.get("api/hackatime/timelapsesForProject",
                                hackatimeUserId: hackatime_user_id, projectKey: project_key)

      unless response.success?
        Rails.logger.error "LapseService timelapsesForProject error: #{response.status} - #{response.body}"
        return []
      end

      body = JSON.parse(response.body)
      return [] unless body["ok"]

      Array(body.dig("data", "timelapses")).select { |tl| tl.is_a?(Hash) }.map(&:symbolize_keys)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "LapseService timelapsesForProject timeout: #{e.message}"
      []
    rescue => e
      Rails.logger.error "LapseService timelapsesForProject exception: #{e.message}"
      []
    end

    # A fresh connection per call: cheap, and keeps concurrent key fetches from
    # sharing one Faraday instance across threads.
    def connection
      Faraday.new(url: BASE_URL) do |conn|
        conn.options.open_timeout = OPEN_TIMEOUT
        conn.options.timeout = READ_TIMEOUT
        conn.headers["Authorization"] = "Bearer #{API_KEY}"
        conn.headers["Content-Type"] = "application/json"
        conn.headers["User-Agent"] = Rails.application.config.user_agent
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
