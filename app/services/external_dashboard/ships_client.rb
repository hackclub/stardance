module ExternalDashboard
  # Paginated, non-destructive GET /api/v1/certifications/ships - unlike
  # /certifications/approved?refetch=true, safe to call on a schedule.
  class ShipsClient
    PATH = "/api/v1/certifications/ships".freeze
    DEFAULT_LIMIT = 1000
    MAX_PAGES = 25
    MAX_BODY_BYTES = 10.megabytes

    Result = Struct.new(:ships, :status, :error, keyword_init: true)

    def self.fetch_all(...) = new(...).fetch_all

    def initialize(updated_since:, status: "all", limit: DEFAULT_LIMIT)
      @updated_since = updated_since
      @status = status
      @limit = limit
    end

    def fetch_all
      return Result.new(ships: [], status: :not_configured, error: Client::NOT_CONFIGURED_ERROR) unless Client.configured?

      ships = []
      cursor = nil
      until_param = nil
      more = false
      conn = Client.connection

      MAX_PAGES.times do
        response = conn.get(PATH, page_params(cursor: cursor, until_param: until_param))
        raw_body = response.body.to_s

        if raw_body.bytesize > MAX_BODY_BYTES
          return partial_or_error(ships, "response body exceeded #{MAX_BODY_BYTES} bytes, refusing to parse")
        end

        body = Client.parse_json(raw_body)

        unless response.status.between?(200, 299)
          return partial_or_error(ships, "http=#{response.status} error=#{Client.error_from(body).inspect}")
        end


        return partial_or_error(ships, "malformed response body (no ships array)") unless body.is_a?(Hash) && body["ships"].is_a?(Array)

        ships.concat(body["ships"])
        until_param ||= body.dig("window", "to")
        more = body["hasMore"] ? true : false
        cursor = body["nextCursor"]
        break unless more && cursor.present?
      end

      return partial_or_error(ships, "hit #{MAX_PAGES}-page cap or malformed pagination with more remaining") if more

      Result.new(ships: ships, status: :ok)
    rescue Faraday::Error => e
      partial_or_error(ships, "#{e.class}: #{e.message}")
    end

    private

    attr_reader :updated_since, :status, :limit

    def page_params(cursor:, until_param:)
      {
        updatedSince: updated_since.iso8601,
        status: status,
        limit: limit,
        until: until_param,
        cursor: cursor
      }.compact
    end

    def partial_or_error(ships, reason)
      Rails.logger.warn "[ExternalDashboard::ShipsClient] #{reason}"
      Result.new(ships: ships, status: ships.any? ? :partial : :error, error: reason)
    end
  end
end
