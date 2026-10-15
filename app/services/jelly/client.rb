module Jelly
  # Thin wrapper over the Jelly conversations API.
  #
  # Jelly exposes conversation CRUD only: there is no stats, SLA or
  # response-time endpoint, so every metric on the dashboard is derived from
  # these two calls and stored locally. Limits are 100k requests/day and 5k per
  # 5 minutes per IP, which is why the sync is incremental rather than a full
  # refetch.
  class Client
    # Trailing slash matters: Faraday treats a leading-slash path as absolute and
    # would drop the /api prefix.
    BASE_URL = "https://app.letsjelly.com/api/".freeze
    PAGE_LIMIT = 100

    Error = Class.new(StandardError)

    def self.configured? = ENV["JELLY_API_TOKEN"].present?

    def initialize(token: ENV["JELLY_API_TOKEN"])
      raise Error, "JELLY_API_TOKEN not configured" if token.blank?

      @token = token
    end

    # Yields each page of conversations. The caller stops paging once it
    # reaches already-synced records, so this never walks the whole mailbox
    # after the first run.
    def conversations(status: nil, cursor: nil)
      get("conversations", { status: status, limit: PAGE_LIMIT, cursor: cursor }.compact)
    end

    def messages(conversation_id, cursor: nil)
      get("conversations/#{conversation_id}/messages", { limit: PAGE_LIMIT, cursor: cursor }.compact)
    end

    private

    def get(path, params)
      response = connection.get(path, params)
      raise Error, "Jelly API returned #{response.status}" unless response.success?

      JSON.parse(response.body)
    rescue Faraday::Error => e
      raise Error, "Could not reach Jelly: #{e.message}"
    rescue JSON::ParserError
      raise Error, "Jelly returned an unparseable response"
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.headers["Authorization"] = "Bearer #{@token}"
        f.options.timeout = 15
        f.options.open_timeout = 5
      end
    end
  end
end
