class Project::PostToMagicJob < ApplicationJob
  queue_as :default

  CHANNEL_ID = "C0A38L9MFEE"

  include Rails.application.routes.url_helpers

  def perform(project)
    owner = project.memberships.owner.first&.user
    return unless owner

    SendSlackDmJob.perform_later(
      CHANNEL_ID,
      nil,
      blocks_path: "notifications/magic_happening",
      locals: {
        project_title: project.title,
        project_description: project.description.to_s,
        project_url: project_url(project, host: "stardance.hackclub.com", protocol: "https"),
        owner_name: owner.display_name
      }
    )
  end
end
