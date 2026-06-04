# frozen_string_literal: true

module Projects
  class ShelfCardComponent < ViewComponent::Base
    attr_reader :project, :source, :position, :feed_request_id

    def initialize(project:, source: nil, position: nil, feed_request_id: nil)
      @project = project
      @source = source
      @position = position
      @feed_request_id = feed_request_id
    end

    def description
      project.display_description.presence || project.description
    end

    def engagement_data
      {
        controller: "feed-engagement",
        feed_engagement_item_type_value: "project",
        feed_engagement_project_id_value: project.id,
        feed_engagement_source_value: source,
        feed_engagement_position_value: position,
        feed_engagement_feed_request_id_value: feed_request_id
      }.compact
    end
  end
end
