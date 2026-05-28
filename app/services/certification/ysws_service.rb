module Certification
  class YswsService
    GITHUB_CONTRIBUTIONS_API = "https://github-contributions-api.jogruber.de"

    # Fetch contribution stats for a given platform and username
    # Returns a hash with contribution data or error state
    # Example: { total: 31 } or { error: :org_repo } or { error: :fetch_failed }
    def self.fetch_contributions(platform, username)
      return { error: :no_username } if username.blank?

      case platform
      when "github"
        fetch_github_contributions(username)
      when "gitlab"
        # TODO: Implement GitLab API when available
        { error: :unsupported_platform }
      when "codeberg"
        # TODO: Implement Codeberg API when available
        { error: :unsupported_platform }
      else
        { error: :unsupported_platform }
      end
    end

    class << self
      private

      # Fetch GitHub contributions for the last 365 days
      def fetch_github_contributions(username)
        response = github_connection.get("/v4/#{username}")

        case response.status
        when 200
          data = JSON.parse(response.body)
          contributions = filter_last_365_days(data["contributions"])
          total = contributions.sum { |day| day["count"] }
          { total: total, contributions: contributions }
        when 404
          { error: :org_repo }
        else
          Rails.logger.warn("GitHub API returned #{response.status} for user #{username}")
          { error: :fetch_failed }
        end
      rescue Faraday::TimeoutError => e
        Rails.logger.error("GitHub API timeout for #{username}: #{e.message}")
        { error: :timeout }
      rescue JSON::ParserError => e
        Rails.logger.error("GitHub API JSON parse error for #{username}: #{e.message}")
        { error: :parse_error }
      rescue StandardError => e
        Rails.logger.error("GitHub API error for #{username}: #{e.message}")
        { error: :fetch_failed }
      end

      def github_connection
        @github_connection ||= Faraday.new(url: GITHUB_CONTRIBUTIONS_API) do |conn|
          conn.options.timeout = 5
          conn.options.open_timeout = 5
          conn.headers["Content-Type"] = "application/json"
          conn.headers["User-Agent"] = Rails.application.config.user_agent
        end
      end
    end

    # Filter contributions to only include the last 365 days
    def self.filter_last_365_days(contributions)
      return [] if contributions.blank?

      today = Date.today
      one_year_ago = today - 365

      contributions.select do |day|
        date = Date.parse(day["date"])
        date >= one_year_ago && date <= today
      rescue ArgumentError => e
        Rails.logger.error("Date parsing error in GitHub contributions: #{e.message}")
        false
      end
    end
  end
end
