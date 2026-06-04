# Forwards a finished Lookout session's capture timestamps to Hackatime as
# heartbeats, so the recorded time shows up under the Hackatime project the user
# chose on the recorder (an existing one or a new one) — falling back to this
# project's recorder name — which we then link so its hours count toward the
# Stardance project.
# See https://github.com/hackclub/lookout/blob/main/docs/integration.md
class ForwardLookoutHeartbeatsJob < ApplicationJob
  queue_as :default

  def perform(lookout_session_id, project_name = nil)
    session = LookoutSession.find_by(id: lookout_session_id)
    return unless session

    access_token = session.user&.hackatime_identity&.access_token
    return if access_token.blank?

    # The ingestion endpoint needs the user's Hackatime API key, which we obtain
    # from their OAuth token (Stardance only stores the OAuth token).
    api_key = HackatimeService.fetch_api_key(access_token)
    return if api_key.blank?

    data = LookoutService.fetch_timings(session.token)
    timestamps = data.is_a?(Hash) ? (data["timestamps"] || data["timings"]) : data
    return if timestamps.blank?

    # Use the chosen Hackatime project, or this project's recorder name if none
    # was passed (e.g. an older 1-arg enqueue).
    project_name = project_name.presence || session.project.hackatime_recorder_name
    heartbeats = Array(timestamps).filter_map do |value|
      epoch = parse_epoch(value)
      next unless epoch

      {
        type: "file",
        entity: session.token,
        language: "Lookout",
        category: "coding",
        editor: "Lookout",
        project: project_name,
        time: epoch
      }
    end
    return if heartbeats.empty?

    return unless HackatimeService.push_heartbeats(api_key: api_key, heartbeats: heartbeats)

    link_hackatime_project!(session, project_name)
  end

  private

  # Link the Hackatime project the time was filed under to the Stardance project
  # so its hours count here, without the user linking it by hand. Idempotent on
  # (user, name). Never steals a project already linked to a *different* Stardance
  # project — in that case we just leave the time filed under it. Best-effort
  # (non-bang save): the push already succeeded, so a link hiccup shouldn't fail.
  def link_hackatime_project!(session, name)
    hp = User::HackatimeProject.find_or_initialize_by(user: session.user, name: name)
    return if hp.persisted? && hp.project_id.present? && hp.project_id != session.project_id

    hp.project = session.project
    hp.save
  end

  def parse_epoch(value)
    return value.to_i if value.is_a?(Numeric)
    Time.iso8601(value.to_s).to_i
  rescue ArgumentError, TypeError
    nil
  end
end
