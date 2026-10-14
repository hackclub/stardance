# Works out which of a builder's Lookout sessions already have their time in
# Hackatime, exactly (not heuristically): the forwarder stamps every heartbeat it
# pushes with entity: session.token, so a session is "pushed" iff Hackatime holds
# a heartbeat whose entity equals that token. Powers the ✓/needs-push state on
# /my/timelapses and the per-session finalize page.
#
# Always scans the user's whole recoverable session set (not just the one the
# caller cares about) so a direct finalize link and the list page share one
# coherent per-user cache. Reads raw heartbeats over the sessions' date span,
# chunked so one wide range can't pull an unbounded payload, and intersects their
# entities with the session tokens. Never raises: on any failure it returns an
# empty set, so every session falls back to "needs pushing" (safe, since
# re-sending the same session dedupes in Hackatime).
class LookoutPushStatus
  CACHE_TTL = 10.minutes
  COOLDOWN = 15.seconds
  WINDOW = 31.days

  # The set of this user's session tokens already present in Hackatime.
  def self.pushed_tokens(user:, refresh: false)
    new(user).pushed_tokens(refresh: refresh)
  end

  # Drop the cached verdict, e.g. right after a successful forward so the token
  # shows as pushed on the next load instead of waiting out the TTL.
  def self.expire(user)
    Rails.cache.delete(cache_key_for(user))
  end

  def self.cache_key_for(user) = "lookout_push_status:#{user.id}"

  def initialize(user)
    @user = user
  end

  def pushed_tokens(refresh: false)
    Rails.cache.delete(cache_key) if refresh && !recently_scanned?
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      Rails.cache.write(cooldown_key, true, expires_in: COOLDOWN)
      compute
    end
  end

  private

  def compute
    sessions = LookoutSession.where(user: @user).recoverable.to_a
    return Set.new if sessions.empty?

    api_key = resolve_api_key
    return Set.new if api_key.blank?

    tokens = sessions.map(&:token).to_set
    found = Set.new
    each_window(sessions) do |window_start, window_end|
      HackatimeService.fetch_heartbeats(
        api_key: api_key, start_time: window_start.iso8601, end_time: window_end.iso8601
      ).each do |heartbeat|
        entity = heartbeat["entity"]
        found << entity if tokens.include?(entity)
      end
      break if found == tokens
    end
    found
  end

  def each_window(sessions)
    start_at = sessions.filter_map { |s| s.started_at || s.created_at }.min&.beginning_of_day
    return if start_at.nil?

    cursor = start_at
    now = Time.current
    while cursor < now
      window_end = [ cursor + WINDOW, now ].min
      yield cursor, window_end
      cursor = window_end
    end
  end

  def resolve_api_key
    access_token = @user.hackatime_identity&.access_token
    return nil if access_token.blank?

    HackatimeService.fetch_api_key(access_token)
  end

  def cache_key = self.class.cache_key_for(@user)
  def cooldown_key = "lookout_push_status_cooldown:#{@user.id}"
  def recently_scanned? = Rails.cache.exist?(cooldown_key)
end
