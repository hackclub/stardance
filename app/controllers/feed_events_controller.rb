# frozen_string_literal: true

class FeedEventsController < ApplicationController
  skip_before_action :remember_page
  skip_before_action :verify_authenticity_token, only: :create

  EVENT_TYPES = %w[impression read open dwell video_progress hide not_interested].freeze
  GORSE_FEEDBACK_TYPES = {
    "read" => "read",
    "open" => "read",
    "dwell" => "dwell",
    "video_progress" => "watch",
    "hide" => "hide",
    "not_interested" => "not_interested"
  }.freeze

  def create
    if current_user.present?
      event_params.each { |event| record_event(event) }
    end

    head :accepted
  end

  private
    def event_params
      events = params[:events].presence || [ params.except(:controller, :action) ]
      Array(events).filter_map do |event|
        attributes = event.respond_to?(:to_unsafe_h) ? event.to_unsafe_h : event
        permitted = ActionController::Parameters.new(attributes).permit(
          :event_type,
          :item_type,
          :post_id,
          :project_id,
          :post_type,
          :source,
          :position,
          :visible_ms,
          :visibility_ratio,
          :feed_request_id,
          :page,
          :bucket,
          :progress
        )

        permitted.to_h if EVENT_TYPES.include?(permitted[:event_type].to_s)
      end
    end

    def record_event(event)
      if recordable_event?(event)
        ahoy.track("feed_#{event[:item_type]}_#{event[:event_type]}", event)
        send_gorse_feedback(event)
      end
    end

    def recordable_event?(event)
      item = find_item(event)
      item.present? && dedupe_event(event, item)
    end

    def find_item(event)
      @items ||= {}
      @items[event_key(event)] ||= begin
        if event[:item_type] == "project"
          Project.find_by(id: event[:project_id])
        else
          Post.visible_to(current_user).find_by(id: event[:post_id])
        end
      end
    end

    def dedupe_event(event, item)
      key = dedupe_key(event, item)
      if Rails.cache.exist?(key)
        false
      else
        Rails.cache.write(key, true, expires_in: dedupe_ttl(event))
        true
      end
    end

    def dedupe_key(event, item)
      [
        "feed_event",
        current_user.id,
        event[:event_type],
        event[:bucket],
        event[:progress],
        dedupe_feed_request_id(event),
        item.class.name,
        item.id
      ].compact_blank.join("/")
    end

    def dedupe_feed_request_id(event)
      if event[:event_type].in?(%w[impression dwell video_progress])
        event[:feed_request_id]
      end
    end

    def dedupe_ttl(event)
      if event[:event_type].in?(%w[read open hide not_interested])
        1.day
      else
        30.minutes
      end
    end

    def send_gorse_feedback(event)
      feedback_type = GORSE_FEEDBACK_TYPES[event[:event_type]]
      item = find_item(event)
      if feedback_type.present? && item.present?
        item.send_gorse_feedback_later(
          user: current_user,
          item: item,
          feedback_type: feedback_type,
          value: feedback_value(event),
          comment: event[:source]
        )
      end
    end

    def feedback_value(event)
      if event[:event_type] == "dwell"
        event[:bucket].to_i
      elsif event[:event_type] == "video_progress"
        event[:progress].to_i
      else
        1
      end
    end

    def event_key(event)
      [ event[:item_type], event[:post_id], event[:project_id] ].join(":")
    end
end
