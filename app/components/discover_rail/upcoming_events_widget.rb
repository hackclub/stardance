# frozen_string_literal: true

module DiscoverRail
  class UpcomingEventsWidget < BaseWidget
    register_as :upcoming_events

    DEFAULT_API_URL = "https://ambassador.hackclub.com/api/stardance/expeditions"
    DEFAULT_STATUS_API_URL = "https://ambassador.hackclub.com/api/stardance/ambassadors"
    API_URL = ENV.fetch("AMBASSADOR_EXPEDITIONS_API_URL", DEFAULT_API_URL)
    STATUS_API_URL = ENV.fetch("AMBASSADOR_STATUS_API_URL", DEFAULT_STATUS_API_URL)
    API_KEY = ENV["AMBASSADOR_EXPEDITIONS_API_KEY"].presence
    LIMIT = 3
    CACHE_TTL = 15.minutes
    HTTP_TIMEOUT = 3 # seconds; the rail must never stall a pageload

    def events
      @events ||= fetch_events
    end

    def render?
      events.any?
    end

    # Server-rendered fallback (UTC); the event-time Stimulus controller swaps
    # it for the viewer's local time once connected.
    def relative_time(event)
      now = Time.current
      ends_at = event[:end]
      return "happening now" if ends_at && event[:start] <= now && now <= ends_at

      distance = event[:start] - now
      # The visibility filter guarantees start (or end, handled above) is in
      # the future, so a negative distance only happens in a sub-second race.
      return "now" if distance < 1.minute

      if distance < 1.hour
        "in #{(distance / 60).ceil}min"
      elsif distance < 1.day
        "in #{(distance / 3600).round}h"
      elsif distance < 7.days
        event[:start].strftime("%a %-I:%M%P")
      else
        event[:start].strftime("%b %-d")
      end
    end

    def can_post_expeditions?
      return false if user&.slack_id.blank?
      return false if API_KEY.blank?

      Rails.cache.fetch(
        [ "discover_rail", "ambassador_status", STATUS_API_URL, user.slack_id ],
        expires_in: CACHE_TTL
      ) do
        request_ambassador_status(user.slack_id)
      end
    end

    private

    def fetch_events
      return [] if API_KEY.blank?

      # Failures cache as "[]" so a broken API costs one request per TTL, not
      # one per pageload.
      raw = Rails.cache.fetch([ "discover_rail", "ambassador_expeditions", API_URL ], expires_in: CACHE_TTL) do
        request_events || "[]"
      end
      return [] if raw.blank?

      parsed = JSON.parse(raw)
      now = Time.current

      Array(parsed["expeditions"])
        .filter_map { |e| build_event(e) }
        .uniq { |e| e[:slug] }
        .select { |e| e[:start] >= now }
        .sort_by { |e| e[:start] }
        .first(LIMIT)
    rescue JSON::ParserError, StandardError
      []
    end

    # Returns the response body on success, nil otherwise.
    def request_events
      uri = URI(API_URL)
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: HTTP_TIMEOUT,
                                 read_timeout: HTTP_TIMEOUT) do |http|
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["X-Stardance-Data-Access-Key"] = API_KEY
        http.request(request)
      end
      response.is_a?(Net::HTTPSuccess) ? response.body : nil
    rescue StandardError
      nil
    end

    def request_ambassador_status(slack_id)
      uri = URI("#{STATUS_API_URL.chomp("/")}/#{ERB::Util.url_encode(slack_id)}")
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: HTTP_TIMEOUT,
                                 read_timeout: HTTP_TIMEOUT) do |http|
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["X-Stardance-Data-Access-Key"] = API_KEY
        http.request(request)
      end
      return false unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)["ambassador"] == true
    rescue JSON::ParserError, StandardError
      false
    end

    def build_event(data)
      start_time = Time.zone.parse(data["date"].to_s)
      return nil unless start_time

      venue = data["venue"].is_a?(Hash) ? data["venue"] : {}
      city = venue["city"].presence
      state = venue["state"].presence
      country = venue["country"].presence
      location = [ city, state || country ].compact.join(", ").presence

      {
        title: data["prettyName"].presence || data["name"].presence || "Stardance expedition",
        leader: data["ambassadorName"].presence || "Hack Club Ambassador",
        location: location,
        start: start_time,
        end: nil,
        slug: data["slug"].presence || data["id"],
        ama: false,
        avatar: nil,
        url: data["googleMapsUrl"].presence || data["appleMapsUrl"].presence
      }
    rescue ArgumentError
      nil
    end
  end
end
