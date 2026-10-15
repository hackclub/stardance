# Reads a project's historical Lookout recordings for the hardware review pages.
#
# Stardance no longer records with Lookout - builders record on Lapse now - but
# Lookout is still running for the rest of Hack Club, and ~7.3k finished
# recordings are still attached to projects here. Its stored video URLs are
# presigned and expire after ~1h, so the stored recording_url is almost always
# dead and each one has to be refreshed live at render time.
class LookoutService
  BASE_URL = Rails.application.credentials.dig(:lookout, :base_url) || ENV.fetch("LOOKOUT_BASE_URL", "https://lookout.hackclub.com")

  # Bounds for the review-page recording fetch (see recordings_for_project).
  REVIEW_OPEN_TIMEOUT = 3
  REVIEW_READ_TIMEOUT = 6
  MAX_REVIEW_RECORDINGS = 12

  # Bounds for the token-authenticated client API (status/timings/stop), used by
  # the temporary session-finalize recovery flow. See LookoutSessionsController.
  CLIENT_OPEN_TIMEOUT = 5
  CLIENT_READ_TIMEOUT = 10

  class << self
    # Client API (token-authenticated). Current status/duration/video for one
    # session; nil on failure.
    def fetch_session(token)
      response = client_connection.get("api/sessions/#{token}")
      return JSON.parse(response.body).symbolize_keys if response.success?

      Rails.logger.error "LookoutService fetch_session error: #{response.status}"
      nil
    rescue => e
      Rails.logger.error "LookoutService fetch_session exception: #{e.message}"
      nil
    end

    # Capture timestamps for a session, forwarded to Hackatime as heartbeats
    # (see LookoutHeartbeatForwarder). Returns the parsed body (an array, or a
    # hash with a "timestamps" key) or nil.
    def fetch_timings(token)
      response = client_connection.get("api/sessions/#{token}/timings")
      return JSON.parse(response.body) if response.success?

      Rails.logger.error "LookoutService fetch_timings error: #{response.status}"
      nil
    rescue => e
      Rails.logger.error "LookoutService fetch_timings exception: #{e.message}"
      nil
    end

    def stop_session(token)
      response = client_connection.post("api/sessions/#{token}/stop")
      return JSON.parse(response.body).symbolize_keys if response.success?

      Rails.logger.error "LookoutService stop_session error: #{response.status}"
      nil
    rescue => e
      Rails.logger.error "LookoutService stop_session exception: #{e.message}"
      nil
    end

    # A single session's playable recording (live-refreshed presigned URL), or
    # nil when nothing is ready yet. Same display hash as recordings_for_project.
    def recording_for_session(session)
      review_recording(session)
    end

    # A project's finished Lookout recordings, for the hardware funding review.
    # Lookout's stored video URLs are presigned and expire after ~1h, so we
    # refresh each session's video/thumbnail live (concurrently, bounded) at
    # render time. Returns an array of display hashes ({ video_url:,
    # thumbnail_url:, duration:, mode:, recorded_at: }) newest-first, or [] —
    # never raises, since the review page must render regardless.
    def recordings_for_project(project)
      sessions = project.lookout_sessions
                        .attachable
                        .order(Arel.sql("COALESCE(started_at, created_at) DESC"))
                        .limit(MAX_REVIEW_RECORDINGS)
                        .to_a
      return [] if sessions.empty?

      sessions.map { |session| Thread.new { review_recording(session) } }
              .map(&:value)
              .compact
    end

    private

    # Refresh one session's video/thumbnail from Lookout's client API, falling
    # back to the stored (possibly-expired) URL if the live call fails. Returns
    # a display hash, or nil when no playable video exists yet.
    def review_recording(session)
      remote = fetch_session_for_review(session.token)
      video = remote&.values_at(:videoUrl, :video_url, :recording_url)&.compact&.first
      video = session.recording_url if video.blank?
      return nil if video.blank?

      tracked = remote&.values_at(:trackedSeconds, :tracked_seconds)&.compact&.first
      {
        video_url: video,
        thumbnail_url: remote&.values_at(:thumbnailUrl, :thumbnail_url)&.compact&.first,
        duration: (tracked || session.duration_seconds).to_i,
        mode: session.mode,
        recorded_at: session.started_at || session.created_at
      }
    rescue => e
      # Runs inside a Thread whose value is re-raised in the request; an
      # unexpected remote shape must not 500 the review page.
      Rails.logger.error "LookoutService review_recording exception: #{e.message}"
      nil
    end

    # GET /api/sessions/:token on a short-timeout, per-call connection (so the
    # concurrent review fetches don't share one Faraday across threads).
    def fetch_session_for_review(token)
      response = review_connection.get("api/sessions/#{token}")
      return nil unless response.success?

      JSON.parse(response.body).symbolize_keys
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "LookoutService review fetch timeout: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "LookoutService review fetch exception: #{e.message}"
      nil
    end

    def review_connection
      Faraday.new(url: BASE_URL) do |conn|
        conn.options.open_timeout = REVIEW_OPEN_TIMEOUT
        conn.options.timeout = REVIEW_READ_TIMEOUT
        conn.headers["Content-Type"] = "application/json"
        conn.adapter Faraday.default_adapter
      end
    end

    def client_connection
      @client_connection ||= Faraday.new(url: BASE_URL) do |conn|
        conn.options.open_timeout = CLIENT_OPEN_TIMEOUT
        conn.options.timeout = CLIENT_READ_TIMEOUT
        conn.headers["Content-Type"] = "application/json"
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
