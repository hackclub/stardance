module VoteTrackable
  extend ActiveSupport::Concern

  private

  def track_vote_event(event_type, source: "server", assignment: nil, vote: nil,
                       project: nil, ship_event: nil, properties: {})
    return unless current_user

    event = VoteTelemetry.record(
      event_type,
      user: current_user,
      source: source,
      assignment: assignment,
      vote: vote,
      project: project,
      ship_event: ship_event,
      properties: properties,
      ip: client_ip_address,
      user_agent: request.user_agent,
      ahoy_visit_id: current_ahoy_visit_id
    )

    ahoy.track(event_type.to_s, ahoy_vote_properties(event, properties)) if event
    event
  end

  def current_ahoy_visit_id
    ahoy.visit&.id
  rescue StandardError
    nil
  end

  def ahoy_vote_properties(event, properties)
    properties.merge(
      source: event.source,
      vote_event_id: event.id,
      vote_assignment_id: event.vote_assignment_id,
      vote_id: event.vote_id,
      project_id: event.project_id,
      ship_event_id: event.ship_event_id
    ).compact
  end
end
