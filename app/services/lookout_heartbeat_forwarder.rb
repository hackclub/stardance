# Forwards a finished Lookout session's capture timestamps to Hackatime as
# heartbeats, so the recorded time shows up under the Hackatime project the user
# chose on the recorder (an existing one or a new one) — falling back to this
# project's recorder name — which we then link so its hours count toward the
# Stardance project.
# See https://github.com/hackclub/lookout/blob/main/docs/integration.md
#
# Returns a Result so callers can tell the user what happened. The recorder runs
# this synchronously from the "where should this time go?" step and surfaces
# Result#error in the UI when something goes wrong, instead of silently dropping
# the time (which is what the old fire-and-forget job did).
class LookoutHeartbeatForwarder
  # ok?  -> did the time make it to Hackatime
  # error -> a user-facing sentence explaining a failure (nil on success)
  # count -> number of heartbeats sent (0 on failure)
  Result = Data.define(:ok, :error, :count) do
    def ok? = ok
  end

  def self.call(session, project_name: nil)
    new(session, project_name: project_name).call
  end

  def initialize(session, project_name: nil)
    @session = session
    @project_name = project_name
  end

  def call
    access_token = @session.user&.hackatime_identity&.access_token
    return failure("Link your Hackatime account before sending your time.") if access_token.blank?

    # The ingestion endpoint needs the user's Hackatime API key, which we obtain
    # from their OAuth token (Stardance only stores the OAuth token).
    api_key = HackatimeService.fetch_api_key(access_token)
    return failure("We couldn't reach Hackatime to authorize sending your time. Please try again in a moment.") if api_key.blank?

    timestamps = fetch_timestamps
    return failure("Lookout hasn't logged any tracked time for this recording yet, so there's nothing to send.") if timestamps.blank?

    # Use the chosen Hackatime project, or this project's recorder name if none
    # was passed (e.g. an older 1-arg enqueue).
    name = @project_name.presence || @session.project.hackatime_recorder_name
    heartbeats = build_heartbeats(timestamps, name)
    return failure("Lookout hasn't logged any tracked time for this recording yet, so there's nothing to send.") if heartbeats.empty?

    unless HackatimeService.push_heartbeats(api_key: api_key, heartbeats: heartbeats)
      return failure("Hackatime didn't accept your time. Please try again in a moment.")
    end

    link_hackatime_project!(name)
    Result.new(ok: true, error: nil, count: heartbeats.size)
  end

  private

  def fetch_timestamps
    data = LookoutService.fetch_timings(@session.token)
    data.is_a?(Hash) ? (data["timestamps"] || data["timings"]) : data
  end

  def build_heartbeats(timestamps, project_name)
    Array(timestamps).filter_map do |value|
      epoch = parse_epoch(value)
      next unless epoch

      {
        type: "file",
        entity: @session.token,
        language: "Lookout",
        category: "coding",
        editor: "Lookout",
        project: project_name,
        time: epoch
      }
    end
  end

  # Link the Hackatime project the time was filed under to the Stardance project
  # so its hours count here, without the user linking it by hand. Idempotent on
  # (user, name). Never steals a project already linked to a *different* Stardance
  # project — in that case we just leave the time filed under it. Best-effort
  # (non-bang save): the push already succeeded, so a link hiccup shouldn't fail.
  def link_hackatime_project!(name)
    hp = User::HackatimeProject.find_or_initialize_by(user: @session.user, name: name)
    return if hp.persisted? && hp.project_id.present? && hp.project_id != @session.project_id

    hp.project = @session.project
    hp.save
  end

  def parse_epoch(value)
    return value.to_i if value.is_a?(Numeric)
    Time.iso8601(value.to_s).to_i
  rescue ArgumentError, TypeError
    nil
  end

  def failure(message)
    Result.new(ok: false, error: message, count: 0)
  end
end
