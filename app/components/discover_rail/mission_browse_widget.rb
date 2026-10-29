# frozen_string_literal: true

module DiscoverRail
  class MissionBrowseWidget < BaseWidget
    register_as :mission_browse

    def project
      context[:project]
    end

    def render?
      project.present? &&
        project.mission_attachable? &&
        user.present? &&
        project.users.exists?(id: user.id)
    end
  end
end
