class HackatimeService
  BASE_URL = "https://hackatime.hackclub.com"
  START_DATE = "2026-05-31"

  class << self
    def fetch_authenticated_user(access_token)
      response = connection.get("authenticated/me") do |req|
        req.headers["Authorization"] = "Bearer #{access_token}"
      end

      if response.success?
        JSON.parse(response.body)["id"]&.to_s
      else
        Rails.logger.error "HackatimeService authenticated/me error: #{response.status}"
        nil
      end
    rescue => e
      Rails.logger.error "HackatimeService authenticated/me exception: #{e.message}"
      nil
    end

    def fetch_stats(hackatime_uid, start_date: START_DATE, end_date: nil, access_token: nil)
      params = { features: "projects", start_date: start_date, test_param: true }
      params[:end_date] = end_date if end_date

      response = stats_request(hackatime_uid, params, access_token: access_token)

      if response.success?
        data = JSON.parse(response.body)
        projects = data.dig("data", "projects") || []
        {
          projects: projects.reject { |p| User::HackatimeProject::EXCLUDED_NAMES.include?(p["name"]) }
                            .to_h { |p| [ p["name"], p["total_seconds"].to_i ] },
          banned: data.dig("trust_factor", "trust_value") == 1
        }
      else
        Rails.logger.error "HackatimeService error: #{response.status} - #{response.body}"
        nil
      end
    rescue => e
      Rails.logger.error "HackatimeService exception: #{e.message}"
      nil
    end

    def fetch_total_seconds_for_projects(hackatime_uid, project_keys, start_date: START_DATE, end_date: nil, access_token: nil)
      return nil if hackatime_uid.blank? || project_keys.blank?

      params = {
        features: "projects",
        start_date: start_date,
        test_param: true,
        total_seconds: true,
        filter_by_project: Array(project_keys).join(",")
      }
      params[:end_date] = end_date if end_date

      response = stats_request(hackatime_uid, params, access_token: access_token)

      if response.success?
        JSON.parse(response.body)["total_seconds"].to_i
      else
        Rails.logger.error "HackatimeService.fetch_total_seconds_for_projects error: #{response.status} - #{response.body}"
        nil
      end
    rescue => e
      Rails.logger.error "HackatimeService.fetch_total_seconds_for_projects exception: #{e.message}"
      nil
    end

    private

      def stats_request(hackatime_uid, params, access_token: nil)
        if access_token.present?
          api_key = resolve_api_key(hackatime_uid, access_token)
          if api_key
            return connection.get("users/my/stats", params) do |req|
              req.headers["Authorization"] = "Bearer #{api_key}"
            end
          end
        end

        connection.get("users/#{hackatime_uid}/stats", params)
      end

      def resolve_api_key(hackatime_uid, access_token)
        cache_key = "hackatime_api_key:#{hackatime_uid}"
        cached = Rails.cache.read(cache_key)
        return cached if cached.present?

        key = fetch_api_key(access_token)
        Rails.cache.write(cache_key, key, expires_in: 1.week) if key.present?
        key
      end

      def fetch_api_key(access_token)
        response = connection.get("authenticated/api_keys") do |req|
          req.headers["Authorization"] = "Bearer #{access_token}"
        end

        if response.success?
          JSON.parse(response.body)["token"]
        else
          Rails.logger.error "HackatimeService.fetch_api_key error: #{response.status}"
          nil
        end
      rescue => e
        Rails.logger.error "HackatimeService.fetch_api_key exception: #{e.message}"
        nil
      end

      def connection
        @connection ||= Faraday.new(url: "#{BASE_URL}/api/v1") do |conn|
          conn.headers["Content-Type"] = "application/json"
          conn.headers["User-Agent"] = Rails.application.config.user_agent
          conn.headers["RACK_ATTACK_BYPASS"] = ENV["HACKATIME_BYPASS_KEYS"] if ENV["HACKATIME_BYPASS_KEYS"].present?
        end
      end
  end
end
