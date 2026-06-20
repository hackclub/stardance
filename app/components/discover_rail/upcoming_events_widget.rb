# frozen_string_literal: true

module DiscoverRail
  class UpcomingEventsWidget < BaseWidget
    register_as :upcoming_events

    API_URL = "https://events.hackclub.com/api/events/upcoming/"
    # The API returns every Hack Club event; we only surface Stardance's own.
    STARDANCE_TAG = "stardance"
    LIMIT = 3
    CACHE_TTL = 15.minutes

    # Hand-curated events the API doesn't carry (or doesn't tag as Stardance).
    # Past entries drop out of the rail automatically — prune them here once
    # they're stale.
    PINNED_EVENTS = [
      {
        title: "AMA: Artemis I Flight Director Elias Myrmo",
        leader: "Elias Myrmo",
        start: "2026-06-12T21:00:00Z", # Fri June 12, 5pm EDT
        end: "2026-06-12T22:00:00Z", # announcement gives no end; assume an hour
        slug: "eliasmyrmo",
        ama: true,
        avatar: "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcR44FWKqT-m6yTSq_GX1VsFf5HN-KTP5sZTSA&s",
        url: "https://lu.ma/eliasmyrmo"
      }
    ].freeze
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

    private

    def fetch_events
      # Failures cache as "[]" so a broken API costs one request per TTL, not
      # one per pageload.
      raw = Rails.cache.fetch("discover_rail/upcoming_events", expires_in: CACHE_TTL) do
        request_events || "[]"
      end
      return [] if raw.blank?

      parsed = JSON.parse(raw)
      now = Time.current

      api_events = parsed
        .select { |e| Array(e["tags"]).include?(STARDANCE_TAG) }
        .filter_map { |e| build_event(e) }

      (pinned_events + api_events)
        .uniq { |e| e[:slug] }
        .select { |e| (e[:end] || e[:start]) >= now } # stays up while running
        .sort_by { |e| e[:start] }
        .first(LIMIT)
    rescue JSON::ParserError, StandardError
      []
    end

    def pinned_events
      PINNED_EVENTS.map do |e|
        e.merge(start: Time.zone.parse(e[:start]), end: e[:end] && Time.zone.parse(e[:end]))
      end
    end

    # Returns the response body on success, nil otherwise. The URL must keep
    # its trailing slash — the API 308s the slashless form and Net::HTTP
    # doesn't follow redirects.
    def request_events
      uri = URI(API_URL)
      response = Net::HTTP.start(uri.host, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: HTTP_TIMEOUT,
                                 read_timeout: HTTP_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
      response.is_a?(Net::HTTPSuccess) ? response.body : nil
    rescue StandardError
      nil
    end

    def build_event(data)
      start_time = Time.zone.parse(data["start"])
      return nil unless start_time

      {
        title: data["title"],
        leader: data["leader"],
        start: start_time,
        end: data["end"].present? ? Time.zone.parse(data["end"]) : nil,
        slug: data["slug"],
        ama: data["ama"] == true,
        avatar: data["avatar"],
        url: data["cal"].presence
      }
    rescue ArgumentError
      nil
    end
  end
end
