# frozen_string_literal: true

class Feed::SessionStore
  SESSION_TTL = 30.minutes
  SERVED_TTL = 2.hours
  SUPPRESSION_TTL = 30.days
  SESSION_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  attr_reader :cache_healthy

  def initialize(user:, cache: Rails.cache)
    @user = user
    @cache = cache
    @cache_healthy = true
  end

  def read_session(session_id)
    return unless valid_session_id?(session_id)

    safe_cache { cache.read(session_key(session_id)) }
  end

  def write_session(session_id, entries:, base_offset:)
    return false unless valid_session_id?(session_id)

    safe_cache(false) do
      cache.write(
        session_key(session_id),
        { entries: entries, base_offset: base_offset },
        expires_in: SESSION_TTL
      )
    end
  end

  def served_at
    now = Time.current.to_i
    cutoff = now - SERVED_TTL.to_i
    values = safe_cache({}) { cache.read(served_key) } || {}
    values.each_with_object({}) do |(content_id, timestamp), recent|
      recent[content_id.to_i] = timestamp.to_i if timestamp.to_i >= cutoff
    end
  end

  def mark_served(content_ids, at: Time.current)
    ids = Array(content_ids).compact.map(&:to_i).uniq
    return if ids.empty?

    values = served_at.transform_keys(&:to_s)
    ids.each { |content_id| values[content_id.to_s] = at.to_i }
    safe_cache(false) { cache.write(served_key, values, expires_in: SERVED_TTL) }
  end

  def suppressed_ids
    values = safe_cache([]) { cache.read(suppressed_key) } || []
    values.map(&:to_i).to_set
  end

  def suppress(content_id)
    return if content_id.blank?

    values = suppressed_ids.add(content_id.to_i).to_a
    safe_cache(false) { cache.write(suppressed_key, values, expires_in: SUPPRESSION_TTL) }
  end

  private
    attr_reader :user, :cache

    def valid_session_id?(session_id)
      session_id.to_s.match?(SESSION_ID_PATTERN)
    end

    def session_key(session_id)
      "feed/session/v1/#{user.id}/#{session_id}"
    end

    def served_key
      "feed/served/v1/#{user.id}"
    end

    def suppressed_key
      "feed/suppressed/v1/#{user.id}"
    end

    def safe_cache(fallback = nil)
      yield
    rescue StandardError => error
      @cache_healthy = false
      Rails.logger.warn("[Feed::SessionStore] cache failed: #{error.class}: #{error.message}")
      fallback
    end
end
