# frozen_string_literal: true

class VoteTelemetry
  class << self
    def record(event_type, user:, source: "server", assignment: nil, vote: nil,
               project: nil, ship_event: nil, properties: {},
               ip: nil, user_agent: nil, ahoy_visit_id: nil, mirror_fullstory: true)
      return if user.nil?
      return unless Vote::Event::EVENT_TYPES.include?(event_type.to_s)

      assignment ||= vote&.assignment
      ship_event ||= assignment&.ship_event || vote&.ship_event
      project    ||= ship_event&.project || vote&.project

      event = Vote::Event.create!(
        event_type: event_type.to_s,
        source: source.to_s,
        occurred_at: Time.current,
        user: user,
        vote_assignment: assignment,
        vote: vote,
        project: project,
        ship_event: ship_event,
        ip: ip,
        user_agent: user_agent,
        ahoy_visit_id: ahoy_visit_id,
        properties: properties.to_h
      )

      mirror_to_fullstory_later(event) if mirror_fullstory
      event
    rescue StandardError => e
      Rails.logger.warn("[VoteTelemetry] failed to record #{event_type}: #{e.class}: #{e.message}")
      nil
    end

    private
      def mirror_to_fullstory_later(event)
        return unless fullstory_configured?

        TrackFullstoryEventJob.perform_later(
          user_id: event.user_id,
          name: event.event_type,
          properties: event.properties.merge(fullstory_context(event))
        )
      end

      def fullstory_configured?
        Rails.application.credentials.dig(:fullstory, :api_key).present?
      end

      def fullstory_context(event)
        {
          source: event.source,
          vote_event_id: event.id,
          vote_assignment_id: event.vote_assignment_id,
          vote_id: event.vote_id,
          project_id: event.project_id,
          ship_event_id: event.ship_event_id
        }.compact
      end
  end
end
