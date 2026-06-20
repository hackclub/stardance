class Votes::EventsController < ApplicationController
  include VoteTrackable

  skip_before_action :remember_page

  NUMERIC_PROPERTY_KEYS = %i[
    visible_ms focused_ms hidden_count blur_count max_idle_gap_ms elapsed_ms
    scroll_depth_pct item_index score paste_count pasted_char_count
    word_count char_count typing_ms
  ].freeze
  STRING_PROPERTY_KEYS = %i[item_kind category].freeze
  PROPERTY_KEYS = (NUMERIC_PROPERTY_KEYS + STRING_PROPERTY_KEYS).freeze

  def create
    if current_user.present?
      client_events.each { |event| record_client_event(event) }
    end

    head :accepted
  end

  private
    def client_events
      raw = params[:events].presence || [ params.except(:controller, :action) ]
      Array(raw).filter_map do |event|
        attributes = event.respond_to?(:to_unsafe_h) ? event.to_unsafe_h : event
        permitted = ActionController::Parameters.new(attributes).permit(
          :event_type,
          :vote_assignment_id,
          properties: PROPERTY_KEYS
        )
        permitted if Vote::Event::CLIENT_EVENT_TYPES.include?(permitted[:event_type].to_s)
      end
    end

    def record_client_event(event)
      assignment = find_assignment(event[:vote_assignment_id])
      return unless assignment

      track_vote_event(event[:event_type],
                       source: "client",
                       assignment: assignment,
                       properties: event_properties(event))
    end

    def find_assignment(id)
      return if id.blank?

      @assignments ||= {}
      @assignments[id] ||= current_user.vote_assignments.find_by(id: id)
    end

    def event_properties(event)
      props = event[:properties]&.to_h || {}
      props.each_with_object({}) do |(key, value), out|
        out[key] = NUMERIC_PROPERTY_KEYS.include?(key.to_sym) ? value.to_i : value
      end
    end
end
