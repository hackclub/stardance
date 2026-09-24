class HackatimeService
  BASE_URL = "https://hackatime.hackclub.com"
  START_DATE = "2026-05-31"
  # Tags the heartbeat that brings a project into existence, so it is
  # distinguishable from real activity (e.g. by Hackatime fraud tooling).
  SEED_PLUGIN = "stardance-project-seed".freeze

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
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService authenticated/me timeout: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "HackatimeService authenticated/me exception: #{e.message}"
      nil
    end

    def lookup_user_id_by_email(email)
      return nil if email.blank?

      response = admin_connection.post("user/get_user_by_email") do |req|
        req.headers["Authorization"] = "Bearer #{ENV["HACKATIME_ADMIN_KEY"]}"
        req.body = { email: email }.to_json
      end

      if response.success?
        JSON.parse(response.body)["user_id"]
      elsif response.status == 404
        nil # email not known to Hackatime
      else
        Rails.logger.error "HackatimeService get_user_by_email error: #{response.status}"
        nil
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService get_user_by_email timeout: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "HackatimeService get_user_by_email exception: #{e.message}"
      nil
    end

    def fetch_stats(hackatime_uid, start_date: START_DATE, end_date: nil, access_token: nil)
      params = { features: "projects", start_date: start_date, test_param: true, no_ai_coding: false, _t: Time.now.to_i }
      params[:end_date] = end_date if end_date

      response, fell_back = stats_request(hackatime_uid, params, access_token: access_token)

      if response.success?
        data = JSON.parse(response.body)
        projects = data.dig("data", "projects") || []
        {
          projects: projects.reject { |p| User::HackatimeProject::EXCLUDED_NAMES.include?(p["name"]) }
                            .to_h { |p| [ p["name"], p["total_seconds"].to_i ] },
          banned: data.dig("trust_factor", "trust_value") == 1,
          token_stale: fell_back
        }
      else
        Rails.logger.error "HackatimeService error: #{response.status} - #{response.body}"
        nil
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService timeout: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "HackatimeService exception: #{e.message}"
      nil
    end

    # works in all circumstances, even if the user is banned (api locked) and has private data
    def fetch_trust_level(hackatime_uid)
      return nil if hackatime_uid.blank?

      response = connection.get("users/#{hackatime_uid}/trust_factor")
      if response.success?
        JSON.parse(response.body)["trust_level"]
      else
        Rails.logger.error "HackatimeService trust_factor error: #{response.status} - #{response.body}"
        nil
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService trust_factor timeout: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "HackatimeService trust_factor exception: #{e.message}"
      nil
    end

    # raw trust levels from Hackatime (admin batch api, fast, max 2000 uids)
    def fetch_trust_levels(hackatime_uids)
      return {} if hackatime_uids.blank?

      response = admin_connection.get("user/info_batch", ids: hackatime_uids.join(",")) do |req|
        req.headers["Authorization"] = "Bearer #{ENV["HACKATIME_ADMIN_KEY"]}"
      end

      if response.success?
        JSON.parse(response.body).fetch("users").to_h { |user| [ user["id"].to_s, user["trust_level"] ] }
      else
        Rails.logger.error "HackatimeService user/info_batch error: #{response.status} - #{response.body}"
        nil
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService user/info_batch timeout: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "HackatimeService user/info_batch exception: #{e.message}"
      nil
    end

    def fetch_total_seconds_for_projects(hackatime_uid, project_keys, start_date: START_DATE, end_date: nil, access_token: nil)
      return nil if hackatime_uid.blank? || project_keys.blank?

      params = {
        features: "projects",
        start_date: start_date,
        test_param: true,
        total_seconds: true,
        no_ai_coding: false,
        filter_by_project: Array(project_keys).join(","),
        _t: Time.now.to_i
      }
      params[:end_date] = end_date if end_date

      response, _ = stats_request(hackatime_uid, params, access_token: access_token)
      Rails.logger.info(response.env.url)

      if response.success?
        data = JSON.parse(response.body)
        seconds = data["total_seconds"]
        if seconds.nil?
          projects = data.dig("data", "projects") || []
          seconds = projects.sum { |p| p["total_seconds"].to_i }
        end
        seconds.to_i
      else
        Rails.logger.error "HackatimeService.fetch_total_seconds_for_projects error: #{response.status} - #{response.body}"
        nil
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService.fetch_total_seconds_for_projects timeout: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "HackatimeService.fetch_total_seconds_for_projects exception: #{e.message}"
      nil
    end

    # Exchange a user's OAuth access token for their Hackatime API key (the
    # credential the heartbeat-ingestion endpoint requires). The endpoint
    # returns an existing key or creates one. Returns the key string or nil.
    #
    # MUST stay public: it's called both internally (resolve_api_key) and with an
    # explicit receiver by Project::EnsureHackatimeProjectsJob. Do NOT add a second
    # definition below the `private` keyword — a later same-name def shadows this
    # one and makes it private, which silently breaks every external caller with
    # `NoMethodError (private method 'fetch_api_key')`.
    def fetch_api_key(access_token)
      return nil if access_token.blank?

      response = connection.get("authenticated/api_keys") do |req|
        req.headers["Authorization"] = "Bearer #{access_token}"
      end

      if response.success?
        JSON.parse(response.body)["token"]
      else
        Rails.logger.error "HackatimeService fetch_api_key error: #{response.status} - #{response.body}"
        nil
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService fetch_api_key timeout: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "HackatimeService fetch_api_key exception: #{e.message}"
      nil
    end

    # Push heartbeats to Hackatime on behalf of a user using their API key (NOT
    # the OAuth token — the Wakatime-compatible ingestion endpoint wants the key,
    # which you can get via fetch_api_key). Used to seed the Hackatime project a
    # hardware builder records Lapse timelapses against (see create_project).
    # Returns true on success.
    def push_heartbeats(api_key:, heartbeats:)
      return false if api_key.blank? || heartbeats.blank?

      all_success = true
      heartbeats.each_slice(100) do |slice|
        response = heartbeat_connection.post("users/current/heartbeats.bulk") do |req|
          req.headers["Authorization"] = "Bearer #{api_key}"
          req.body = slice.to_json
        end

        unless response.success?
          Rails.logger.error "HackatimeService push_heartbeats error: #{response.status} - #{response.body}"
          all_success = false
        end
      end

      all_success
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService push_heartbeats timeout: #{e.message}"
      false
    rescue => e
      Rails.logger.error "HackatimeService push_heartbeats exception: #{e.message}"
      false
    end

    # Bring a Hackatime project into existence for the owner of `api_key`.
    #
    # Hackatime has no project resource to POST to: a "project" is just a
    # DISTINCT over the `project` column of heartbeats (hackclub/hackatime
    # ProjectStatsQuery), so a project exists exactly when some heartbeat carries
    # its name. One heartbeat is therefore both necessary and sufficient.
    #
    # Seeding adds no time. Hackatime derives duration from the gap to the
    # previous heartbeat and scores the first one in a project as zero
    # (`LAG(time) ... IS NULL THEN 0` in DashboardData::Snapshots), so the seed
    # can't invent payable hours.
    #
    # The heartbeat is labelled as a project-creation seed rather than left to
    # pass for real activity. Hackatime's ingest endpoint drops anything outside
    # its HEARTBEAT_KEYS allowlist, so there's no custom field to use: `plugin`
    # is the Wakatime-standard "what sent this", and `editor`/`language` are what
    # its dashboards and fraud tooling group on.
    def create_project(api_key:, name:, entity:)
      return false if api_key.blank? || name.blank?

      push_heartbeats(api_key: api_key, heartbeats: [ {
        type: "app",
        entity: entity,
        project: name,
        category: "coding",
        editor: "Stardance",
        language: "Stardance",
        plugin: SEED_PLUGIN,
        time: Time.current.to_i
      } ])
    end

    def fetch_heartbeat_spans(hackatime_uid, project_keys, start_date:, end_date:, access_token: nil)
      return [] if hackatime_uid.blank?

      params = { start_date: start_date, end_date: end_date }
      params[:filter_by_project] = Array(project_keys).join(",") if project_keys.present?

      response = spans_request(hackatime_uid, params, access_token: access_token)

      if response.success?
        JSON.parse(response.body)["spans"] || []
      else
        Rails.logger.error "HackatimeService.fetch_heartbeat_spans error: #{response.status}"
        []
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService.fetch_heartbeat_spans timeout: #{e.message}"
      []
    rescue => e
      Rails.logger.error "HackatimeService.fetch_heartbeat_spans exception: #{e.message}"
      []
    end

    # Raw heartbeats for the api_key's owner between start_time and end_time (both
    # ISO8601). Returns an array of heartbeat hashes (string keys, including
    # "entity" and "project"), or [] on failure. Used to check whether a Lookout
    # session's time already reached Hackatime by matching heartbeat "entity"
    # against the session token (see LookoutPushStatus). The endpoint applies no
    # result cap, so callers bound the window themselves.
    def fetch_heartbeats(api_key:, start_time:, end_time:)
      return [] if api_key.blank?

      response = connection.get("my/heartbeats") do |req|
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.params["start_time"] = start_time
        req.params["end_time"] = end_time
      end

      if response.success?
        JSON.parse(response.body)["heartbeats"] || []
      else
        Rails.logger.error "HackatimeService.fetch_heartbeats error: #{response.status}"
        []
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "HackatimeService.fetch_heartbeats timeout: #{e.message}"
      []
    rescue => e
      Rails.logger.error "HackatimeService.fetch_heartbeats exception: #{e.message}"
      []
    end

    private

      # Returns [response, fell_back] where fell_back is true when the
      # authenticated path failed and we used the public API instead.
      def stats_request(hackatime_uid, params, access_token: nil)
        if access_token.present?
          api_key = resolve_api_key(hackatime_uid, access_token)
          if api_key
            response = connection.get("users/my/stats", params) do |req|
              req.headers["Authorization"] = "Bearer #{api_key}"
            end
            return [ response, false ] if response.success?

            Rails.cache.delete("hackatime_api_key:#{hackatime_uid}")
            fresh_key = fetch_api_key(access_token)
            if fresh_key
              Rails.cache.write("hackatime_api_key:#{hackatime_uid}", fresh_key, expires_in: 1.week)
              response = connection.get("users/my/stats", params) do |req|
                req.headers["Authorization"] = "Bearer #{fresh_key}"
              end
              return [ response, false ] if response.success?
            end
          end

          Rails.logger.warn "HackatimeService falling back to public API for uid=#{hackatime_uid} (token may be stale)"
        end

        [ connection.get("users/#{hackatime_uid}/stats", params), access_token.present? ]
      end

      def spans_request(hackatime_uid, params, access_token: nil)
        if access_token.present?
          api_key = resolve_api_key(hackatime_uid, access_token)
          if api_key
            response = connection.get("users/my/heartbeats/spans", params) do |req|
              req.headers["Authorization"] = "Bearer #{api_key}"
            end
            return response if response.success?
          end
        end

        connection.get("users/#{hackatime_uid}/heartbeats/spans", params)
      end

      def resolve_api_key(hackatime_uid, access_token)
        cache_key = "hackatime_api_key:#{hackatime_uid}"
        cached = Rails.cache.read(cache_key)
        return cached if cached.present?

        key = fetch_api_key(access_token)
        Rails.cache.write(cache_key, key, expires_in: 1.week) if key.present?
        key
      end

      # Admin endpoints live under a different path prefix than the public API.
      def admin_connection
        @admin_connection ||= Faraday.new(url: "#{BASE_URL}/api/admin/v1") do |conn|
          conn.options.open_timeout = 10
          conn.options.timeout = 15
          conn.headers["Content-Type"] = "application/json"
          conn.headers["User-Agent"] = Rails.application.config.user_agent
        end
      end

      def connection
        @connection ||= Faraday.new(url: "#{BASE_URL}/api/v1") do |conn|
          conn.options.open_timeout = 10
          conn.options.timeout = 15
          conn.headers["Content-Type"] = "application/json"
          conn.headers["Cache-Control"] = "no-cache, no-store"
          conn.headers["User-Agent"] = Rails.application.config.user_agent
          conn.headers["RACK_ATTACK_BYPASS"] = ENV["HACKATIME_BYPASS_KEYS"] if ENV["HACKATIME_BYPASS_KEYS"].present?
        end
      end

      # Heartbeats live under a different path prefix than the stats API.
      def heartbeat_connection
        @heartbeat_connection ||= Faraday.new(url: "#{BASE_URL}/api/hackatime/v1") do |conn|
          conn.options.open_timeout = 10
          conn.options.timeout = 15
          conn.headers["Content-Type"] = "application/json"
          conn.headers["User-Agent"] = Rails.application.config.user_agent
        end
      end
  end
end
