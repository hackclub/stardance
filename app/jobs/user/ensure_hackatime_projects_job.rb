# Seeds Hackatime projects for the hardware projects a member already had when
# they linked their Hackatime account.
#
# Project::EnsureHackatimeProjectsJob is event-driven: it fires when a project
# turns hardware, gets renamed, or gains a member. None of those re-fire on a
# link, and the seeding it does needs an access token, so a member who creates
# hardware projects before connecting Hackatime (or whose token was missing or
# revoked at the time) ends up with projects that have no Hackatime project to
# record against. Lapse then has nowhere to file their timelapses.
#
# Fans out one seeding job per project so every guard stays in one place: this
# job decides which projects to look at, that one decides what to do with each.
class User::EnsureHackatimeProjectsJob < ApplicationJob
  queue_as :literally_whenever

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user&.hackatime_identity&.access_token.blank?

    user.projects.hardware.without_hackatime_project_for(user).find_each do |project|
      Project::EnsureHackatimeProjectsJob.perform_later(project.id)
    end
  end
end
